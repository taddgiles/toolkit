#!/usr/bin/env bash
# Release the persistent lock branch after an issue is fully processed.
# Usage: bash release.sh <issue-number>
# Called by the processor sub-agent after merge, escalation, or retry.

set -uo pipefail

ISSUE="${1:?Usage: release.sh <issue-number>}"
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null) || exit 0

gh api "repos/${REPO}/git/refs/heads/agent-lock/issue-${ISSUE}" \
  -X DELETE > /dev/null 2>&1 || true

echo "LOCK_RELEASED"
