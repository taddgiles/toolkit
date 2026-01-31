---
name: submit-pr
description: Create a PR for the current branch and monitor it until ready for final review. Handles CI failures, review comments, and keeping the PR up-to-date with the base branch.
---

# Submit PR

Create a PR for the current branch and monitor it until ready for final review.

## Instructions

Create a PR and monitor it using parallel background agents. The PR targets `master`.

### Step 1: Create the PR

1. Run `git status` to see current changes
2. Run `git log master..HEAD --oneline` to see commits on this branch
3. Generate a concise PR title (under 70 chars) and brief description based on the commits
4. Create the PR:

   ```bash
   gh pr create --title "<title>" --body "$(cat <<'EOF'
   ## Summary
   <1-3 bullet points>

   ## Test plan
   <brief test checklist>
   EOF
   )" --label "change_type/application"
   ```

5. Capture the PR number from the output

### Step 2: Launch Monitoring Agents

Launch 3 background agents in parallel using the Task tool. All agents should run for up to 2 hours max.

**Agent 1: CI Monitor (use model: sonnet)**

```
Monitor CI for PR #<number>. Loop every 60 seconds for up to 2 hours:

1. Check CI status: `gh pr checks <number> --json name,state,conclusion`
2. If any checks failed:
   - Get failure details from GitHub Actions logs
   - Identify the failing test/lint issue
   - Fix the issue in the codebase
   - Commit with message "fix: <brief description of fix>"
   - Push changes
   - Wait 60 seconds for CI to restart
3. If all checks pass, wait 60 seconds and check again
4. Track: timestamp of last push, CI status

Report back when: all CI checks have been passing for 10+ minutes, or 2 hours elapsed.
```

**Agent 2: Review Monitor (use model: sonnet)**

```
Monitor PR #<number> for review comments. Loop every 60 seconds for up to 2 hours:

1. Fetch comments: `gh pr view <number> --json reviews,comments`
2. For each unaddressed comment:
   - If it's a valid code suggestion: implement the fix, commit, push
   - If it's a question: reply briefly with `gh pr comment <number> --body "<response>"`
   - If suggestion doesn't make sense: reply with brief justification why
3. Mark comments as addressed by replying or resolving
4. Keep responses brief and concise (1-2 sentences max)

Report back when: no pending comments for 10+ minutes, or 2 hours elapsed.
```

**Agent 3: Sync Monitor (use model: haiku)**

```
Keep PR #<number> up-to-date with master. Loop every 2 minutes for up to 2 hours:

1. Check if behind: `gh pr view <number> --json mergeStateStatus`
2. If behind master or has conflicts:
   - `git fetch origin master`
   - `git rebase origin/master`
   - If conflicts: attempt to resolve them automatically
   - `git push --force-with-lease`
3. Track: last rebase timestamp

Report back when: PR is up-to-date and no rebases needed for 10+ minutes, or 2 hours elapsed.
```

### Step 3: Coordination

After launching agents, periodically check their status (every 2 minutes). Use `TaskOutput` with `block: false` to check without blocking.

Track these conditions:

- [ ] 10 minutes since last code push (commit/rebase)
- [ ] CI checks all passing
- [ ] All PR comments addressed
- [ ] PR is up-to-date with master

### Step 4: Completion

When ALL conditions are met, notify the user:

```
═══════════════════════════════════════════════════════════
PR #<number> is ready for final review!

Title: <title>
URL: <pr_url>

Status:
✓ CI passing
✓ Up-to-date with master
✓ All comments addressed
✓ Stable for 10+ minutes

Please review and merge when ready.
═══════════════════════════════════════════════════════════
```

If 2 hours elapse without meeting all conditions, notify user of current status and what's blocking.

## Error Handling

- If CI fails 5+ times on the same test, stop and ask user for help
- If rebase conflicts can't be auto-resolved, stop and ask user for help
- If a reviewer explicitly requests changes that require user decision, pause and notify user

## PR Label

Default label: `change_type/application`

If $ARGUMENTS specifies a different label (e.g., "label: change_type/infrastructure"), use that instead.

## PR Arguments

$ARGUMENTS
