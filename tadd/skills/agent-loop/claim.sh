#!/usr/bin/env bash
# Atomic issue claim for agent-loop.
# Usage: bash claim.sh <issue-number> [label]
# Exit 0 + prints "CLAIM_SUCCESS" = this agent owns the issue.
# Exit 1 + prints "CLAIM_FAILED ..." = another agent got it. Caller MUST skip.
#
# How it works:
#   1. Create a persistent lock branch (git ref creation is atomic — 201 or 422)
#   2. Remove the target label so other pollers stop seeing it
#   3. Add agent-working label + comment
#   The lock branch is NOT deleted on success — it persists until the processor
#   cleans up after merge/escalation. This prevents any late-arriving agent from
#   re-claiming the same issue.
#
# Companion: release.sh deletes the lock branch (called by processor on completion).

set -uo pipefail

ISSUE="${1:?Usage: claim.sh <issue-number> [label]}"
LABEL="${2:-ready-for-agent}"
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null) || {
  echo "CLAIM_FAILED — could not determine repo"
  exit 1
}

DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null) || DEFAULT_BRANCH="main"

# --- Step 1: Atomic lock via git ref creation ---
# Creating a ref is truly atomic in GitHub — returns 201 on success, 422 if it already exists.
# The lock branch persists until explicitly released by release.sh after merge/escalation.
LOCK_REF="refs/heads/agent-lock/issue-${ISSUE}"
HEAD_SHA=$(gh api "repos/${REPO}/git/ref/heads/${DEFAULT_BRANCH}" -q .object.sha 2>/dev/null) || {
  echo "CLAIM_FAILED — could not resolve HEAD sha"
  exit 1
}

LOCK_TMPFILE=$(mktemp)
gh api "repos/${REPO}/git/refs" \
  -X POST \
  -f ref="$LOCK_REF" \
  -f sha="$HEAD_SHA" \
  -i 2>/dev/null > "$LOCK_TMPFILE" || true
LOCK_HTTP=$(awk 'NR==1{print $2}' "$LOCK_TMPFILE")
rm -f "$LOCK_TMPFILE"

if [ "$LOCK_HTTP" != "201" ]; then
  echo "CLAIM_FAILED (lock HTTP ${LOCK_HTTP}) — another agent already claimed #${ISSUE}"
  exit 1
fi

# We hold the lock. Everything below must clean up on failure.
rollback() {
  # Delete the lock branch
  gh api "repos/${REPO}/git/refs/heads/agent-lock/issue-${ISSUE}" -X DELETE > /dev/null 2>&1 || true
  # Re-add the target label so the issue isn't orphaned
  gh api "repos/${REPO}/issues/${ISSUE}/labels" \
    -X POST -f "labels[]=${LABEL}" > /dev/null 2>&1 || true
  # Remove agent-working if we added it
  gh issue edit "$ISSUE" --remove-label "agent-working" > /dev/null 2>&1 || true
}

# --- Step 2: Remove the target label so other pollers stop seeing this issue ---
gh api "repos/${REPO}/issues/${ISSUE}/labels/${LABEL}" \
  -X DELETE > /dev/null 2>&1 || true  # OK if already removed

# --- Step 3: Ensure agent-working label exists in the repo ---
gh label create "agent-working" --color "FBCA04" --description "Issue claimed by an agent" \
  -R "$REPO" > /dev/null 2>&1 || true  # ignore error if it already exists

# --- Step 4: Mark as ours ---
gh issue edit "$ISSUE" --add-label "agent-working" > /dev/null 2>&1 || {
  rollback
  echo "CLAIM_FAILED — could not add agent-working label to #${ISSUE}"
  exit 1
}

# --- Step 5: Comment (lock branch stays — released by release.sh after completion) ---
HOSTNAME=$(hostname 2>/dev/null || echo "unknown")
gh issue comment "$ISSUE" --body "Agent picking up this issue. [host:${HOSTNAME}]" > /dev/null 2>&1 || true

echo "CLAIM_SUCCESS"
exit 0
