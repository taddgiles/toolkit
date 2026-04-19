---
name: agent-loop
model: haiku
description: "Continuously grab GitHub issues labeled ready-for-agent from the current repo, implement them using sub-agents, run local code review, create PRs, and monitor CI. Polls indefinitely until manually stopped."
---

# Agent Loop

Lightweight poller that checks for GitHub issues labeled `ready-for-agent`, then spawns a sub-agent to process each one. Designed to run via `/loop` dynamic mode for maximum token efficiency — haiku handles polling, sonnet/opus handles implementation.

**Invoke with:** `/loop /agent-loop` (dynamic self-pacing) or `/loop 30m /agent-loop` (fixed interval)

## Output Format (MANDATORY)

**All output MUST follow these exact templates. Do NOT add extra commentary, explanations, status summaries, bullet lists, configuration recaps, or emoji. Every line you print must match one of these templates exactly (with values substituted). If a state isn't listed here, print nothing.**

### Startup
```
agent-loop | repo: <owner/repo> | label: <label> | quality: <cmd> | branch: <default-branch>
agent-loop | ready
```

### Poll (no issues found)
```
agent-loop | poll: no issues | next check in <N>s
```

### Issue found
```
agent-loop | found <N> issues
agent-loop | processing #<number> — <title>
```

### Processing result
```
agent-loop | #<number> done | PR: <url>
```
or
```
agent-loop | #<number> claim failed, skipping
```
or
```
agent-loop | #<number> escalated — <reason>
```

### Dependency
```
agent-loop | #<number> blocked by #<dep> — deferring
agent-loop | #<number> unblocked — re-queued
```

### Retry (transient error)
```
agent-loop | #<number> retry — <reason>
```

### Batch drain
```
agent-loop | checking for more issues...
```

### Stop (when user interrupts)
```
agent-loop | stopped | processed: <N> merged, <N> escalated, <N> failed
```
(Tally counts from your output history in this conversation.)

### Rules
- **One line per state transition.** Never print multi-line status blocks.
- **No markdown formatting** (no headers, bullets, bold, code blocks) in output text.
- **No emoji.**
- **No filler** like "Now entering the main agent loop", "Ready to process issues", etc.
- **Sub-agent output is hidden.** Only print the result line when a sub-agent completes.
- All output lines MUST start with `agent-loop | `.

## Prerequisites

On the **first iteration** (no prior `agent-loop |` output in conversation), verify:

1. `gh auth status` succeeds (GitHub CLI authenticated)
2. You are in a git repo (`git rev-parse --is-inside-work-tree`)
3. The repo has a remote (`gh repo view --json nameWithOwner -q .nameWithOwner`)
4. CLAUDE.md exists in the repo root

If any prerequisite fails, tell the user what's missing and **do NOT call ScheduleWakeup** (this ends the loop).

## Scheduling the Next Iteration

Every iteration MUST end by either:
- Calling `ScheduleWakeup` to schedule the next iteration, OR
- NOT calling `ScheduleWakeup` to end the loop (prereq failure, `--max` reached, etc.)

When calling `ScheduleWakeup`, always pass `$ARGUMENTS` (if any) appended to the prompt so they carry forward:
- If invoked as `/agent-loop --poll-interval 10m`, pass `prompt: "/agent-loop --poll-interval 10m"`
- If invoked as `/agent-loop`, pass `prompt: "/agent-loop"`
- If you cannot determine the original invocation, pass `prompt: "/agent-loop"`

## Each Iteration

Each iteration performs ONE poll cycle and optionally processes ONE issue.

### Step 1: Detect Repo and Config

**If you already have repo config from a previous iteration in this conversation, skip the detection and reuse it.** Only run detection on the first iteration or if the config is no longer in context (e.g., after compaction dropped the details).

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
```

Read `CLAUDE.md` from the repo root. Extract:

- **Quality command**: Look for commands like `make quality`, `mix test`, `npm test`, etc. Search for phrases like "before committing", "must pass", "quality suite". Store as `QUALITY_CMD`. If not found, default to "not configured" (processor will skip quality steps).
- **Required reading**: Note any files the agent must read before working (architecture docs, coding standards, ADRs). Store as `REQUIRED_DOCS`. If none, default to "none".

Determine the label to search for. Default: `ready-for-agent`. Override via `$ARGUMENTS` if a bare label name is provided.

On the **first iteration only**, print the startup output line and run prerequisites.

### Step 2: Check for Unblocked Dependencies

```bash
gh issue list --label "waiting-on-dependency" --state open --json number,body --limit 10
```

For each issue, extract dependency issue numbers from the body (patterns like `Depends on: #N`, `Dependencies\n- #N`, `## Dependencies` sections). Check if ALL are closed:

```bash
gh issue view <dep-number> --json state -q .state
```

If ALL dependencies are `CLOSED`:
1. Remove `waiting-on-dependency` label
2. Add the target label (default: `ready-for-agent`)
3. Print: `agent-loop | #<number> unblocked — re-queued`

### Step 3: Query for Issues

**If `$ARGUMENTS` includes `--issue N`**, skip querying. Use that issue number directly and jump to Step 4. After processing, do NOT call ScheduleWakeup (single-issue mode exits after one issue).

```bash
gh issue list --label "<label>" --state open --json number,title,labels --limit 10
```

**Filter out** any issues that already have the `agent-working` label (another agent claimed them).

If no issues remain after filtering:
1. Print: `agent-loop | poll: no issues | next check in <N>s`
2. Call `ScheduleWakeup` with the adaptive delay (see Adaptive Polling below)
3. **Stop. Do not continue to Step 4.**

If issues are found:
1. Print: `agent-loop | found <N> issues`
2. Take the **oldest** issue (first in the list)
3. Continue to Step 4

### Step 4: Process the Issue (Sub-agent)

Print: `agent-loop | processing #<number> — <title>`

Determine the processor model from the issue's labels:
- `opus` label → model: **opus**
- `haiku` label → model: **haiku**
- `sonnet` label or no model label → model: **sonnet** (default)
- If multiple model labels, prefer: opus > sonnet > haiku

Spawn a **general-purpose sub-agent** with the model determined above. Do NOT use `isolation: "worktree"` — the sub-agent works directly in the main workspace. The sub-agent prompt MUST be the full processor prompt from the **Processor Sub-agent Prompt** section below, with all template variables filled in:

- `<ISSUE_NUMBER>`, `<ISSUE_TITLE>`, `<ISSUE_BODY>` — from the issue
- `<QUALITY_CMD>` — from config discovery (or "not configured")
- `<REQUIRED_DOCS>` — from config discovery (or "none")
- `<LABEL>` — the label used to find this issue
- `<DEFAULT_BRANCH>` — the repo's default branch name
- `<SKIP_REVIEW>` — "yes" if `--skip-review` was in `$ARGUMENTS`, "no" otherwise

Wait for the sub-agent to complete. Parse its final output for the result:

- If output contains `RESULT:MERGED <pr-url>` → print done line
- If output contains `RESULT:ESCALATED <reason>` → print escalated line
- If output contains `RESULT:FAILED <reason>` → print escalated line
- If output contains `RESULT:CLAIM_FAILED` → print claim failed line
- If output contains `RESULT:BLOCKED #<dep>` → print blocked line
- If output contains `RESULT:RETRY <reason>` → print: `agent-loop | #<number> retry — <reason>`
- **If output contains NO recognized `RESULT:` line** → the sub-agent exited without completing the pipeline (timeout, context limit, crash). Treat as incomplete — see Step 4a.

### Step 4a: Handle Incomplete Sub-agent (MANDATORY)

**This step runs whenever the sub-agent output does not contain a `RESULT:` line.** Do NOT skip this step. Do NOT proceed to Step 5.

1. Check if a PR exists for this issue:
   ```bash
   gh pr list --head "$(git branch --show-current)" --state open --json number,url -q '.[0]'
   ```
   Also try:
   ```bash
   gh pr list --search "Implements #<ISSUE_NUMBER>" --state all --json number,url,state -q '.[0]'
   ```

2. If a PR exists and is `MERGED`:
   - Run cleanup (close issue, remove `agent-working`, delete branch)
   - Print done line and continue to Step 5.

3. If a PR exists but is `OPEN`:
   - The issue still has `agent-working` label — leave it.
   - Print: `agent-loop | #<number> escalated — sub-agent exited before PR merged`
   - Add `needs-human-review` label.
   - Comment on the issue: "Agent sub-process exited before PR was merged. PR <url> needs manual review/merge."
   - **Do NOT proceed to Step 5. Do NOT process more issues. Call ScheduleWakeup with adaptive delay.**

4. If no PR exists:
   - Remove `agent-working` label, re-add target label.
   - Print: `agent-loop | #<number> retry — sub-agent exited before creating PR`
   - **Do NOT proceed to Step 5. Call ScheduleWakeup with adaptive delay.**

### Step 5: Check for More Issues

**IMPORTANT: Only reach this step if Step 4 produced a terminal result (MERGED, ESCALATED, CLAIM_FAILED, BLOCKED). Never proceed here from an incomplete/ambiguous result.**

After processing, check `--max N` if set: count "done" + "escalated" + "failed" output lines in conversation history. If the count has reached N, do NOT call ScheduleWakeup. Stop.

Otherwise, check if there are more issues in the queue:

```bash
gh issue list --label "<label>" --state open --json number --limit 1
```

If more issues exist:
1. Print: `agent-loop | checking for more issues...`
2. Call `ScheduleWakeup(60, "draining issue queue")` — short delay to process next issue quickly
3. Stop.

If no more issues:
1. Call `ScheduleWakeup` with the adaptive delay (see below)
2. Stop.

## Adaptive Polling

Choose the delay based on your conversation history — you can see your own prior output lines to judge recent activity:

| Condition | Delay | Reason |
|-----------|-------|--------|
| Just finished processing an issue, more in queue | 60s | Drain the batch |
| You processed an issue this iteration or the previous one | 270s | Stay responsive, keep prompt cache warm |
| You've seen only "poll: no issues" for several iterations | 3600s | Deep idle, minimize cost |

The key insight: if nothing has happened recently, poll infrequently. If you just saw activity, stay responsive. You don't need a file to know this — your own output history tells you.

**Override:** If `$ARGUMENTS` includes `--poll-interval Nm`, always use that interval instead of adaptive polling. Convert minutes to seconds.

## Arguments

`$ARGUMENTS` — optional overrides:

- A bare label name to use instead of `ready-for-agent`
- `--max N` — stop the loop after processing N issues (do not call ScheduleWakeup after reaching the limit)
- `--dry-run` — show what would be grabbed without actually doing it
- `--skip-review` — pass through to processor, skips code review steps
- `--issue N` — process a specific issue number instead of querying (exits after one issue)
- `--poll-interval Nm` — override adaptive polling with a fixed interval (e.g. `10m`, `30m`)

## Processor Sub-agent Prompt

This is the complete prompt to pass to the processor sub-agent. Fill in all `<TEMPLATE>` variables before passing. **Do not modify the structure — pass it as-is with variables substituted.**

````
You are an autonomous agent processing a GitHub issue. Complete the full pipeline: claim, implement, review, PR, CI, merge.

## Issue
- Number: #<ISSUE_NUMBER>
- Title: <ISSUE_TITLE>
- Body:
<ISSUE_BODY>

## Project Config
- Quality command: <QUALITY_CMD>
- Required docs to read first: <REQUIRED_DOCS>
- Label for re-queue on rollback: <LABEL>
- Default branch: <DEFAULT_BRANCH>
- Skip code review: <SKIP_REVIEW>

## Pipeline

Execute these steps in order. If any step triggers escalation, skip to the Escalation section.

Use `<DEFAULT_BRANCH>` everywhere this prompt says "the default branch" — for git checkout, diff, rebase, etc.

### 1. Claim the Issue

Run the atomic claim script, passing the label as the second argument:

```bash
bash ~/.claude/skills/agent-loop/claim.sh <ISSUE_NUMBER> <LABEL>
```

- Exit 0 (`CLAIM_SUCCESS`) → continue to step 2.
- Exit 1 (`CLAIM_FAILED`) → print `RESULT:CLAIM_FAILED` and stop immediately. Do not proceed.

### 2. Read Spec and Prepare Branch

1. Fetch the full issue:
   ```bash
   gh issue view <ISSUE_NUMBER> --json title,body,labels
   ```

2. **Check for existing PR.** Before doing any work, check if a PR already exists:
   ```bash
   gh pr list --label agent-generated --state open --search "Implements #<ISSUE_NUMBER>" --json number -q '.[].number'
   ```
   If a PR exists, escalate with reason "PR already exists for this issue" and stop.

3. **Check dependencies.** Scan the issue body for patterns like `Depends on: #N`, `Dependencies\n- #N`, or a `## Dependencies` section. For each referenced issue:
   ```bash
   gh issue view <dep-number> --json state -q .state
   ```
   If ANY dependency is still `OPEN`:
   - Add `waiting-on-dependency` label, remove `agent-working` label
   - Release the lock: `bash ~/.claude/skills/agent-loop/release.sh <ISSUE_NUMBER>`
   - Comment: "Blocked — dependency #<dep> is not yet closed."
   - Print `RESULT:BLOCKED #<dep>` and stop.

4. Determine branch type from issue labels:
   - `bug` → `fix`, `refactor` → `refactor`, `test` → `test`, `docs` → `docs`, `chore` → `chore`
   - default → `feat`

5. **Sync with main and create branch IMMEDIATELY — before any other file operations:**
   ```bash
   git checkout <DEFAULT_BRANCH> && git pull origin <DEFAULT_BRANCH>
   git checkout -b <type>/issue-<ISSUE_NUMBER>-<slug>
   ```
   (Generate slug from issue title: lowercase, spaces to hyphens, strip special chars, max 40 chars)
   Check CLAUDE.md for a branch naming convention override.

6. Read all required docs listed in the project config, plus CLAUDE.md.

### 3. Implement

Spawn a sub-agent (model: use the same model as this agent) with this prompt:

```
You are implementing a GitHub issue in an existing codebase.

Issue #<ISSUE_NUMBER>: <ISSUE_TITLE>
<ISSUE_BODY>

Instructions:
1. You are already on branch `<branch_name>`. Do NOT create a new branch.
2. Read CLAUDE.md in the repo root for project rules and conventions.
3. Read these project docs first: <REQUIRED_DOCS>
4. Implement the issue spec completely. Every acceptance criterion must be satisfied.
5. Commit your work following the project's commit format from CLAUDE.md (default: <type>(<scope>): <description> [#<ISSUE_NUMBER>]).
6. Before your final commit, re-read the issue spec and verify EACH acceptance criterion is met.
7. Run the quality gate: <QUALITY_CMD> — fix any failures before committing. If the quality command is "not configured", skip this.
8. Do NOT create a PR. Do NOT push. Just commit locally.
9. Do NOT create any files that are not part of the implementation (no scratch files, notes, plans, logs, or temporary files). Only create/modify files specified in the issue spec.
```

If the sub-agent fails, escalate with reason "implementation failed".

### 4. Quality Gate

If `<QUALITY_CMD>` is "not configured", skip this step.

Run the quality command locally:

```bash
<QUALITY_CMD>
```

If it fails, attempt to fix (up to 2 retries — read errors, fix, re-run). If still failing after retries, escalate with reason "quality gate failed after retries".

### 5. Code Review (Sub-agents, Parallel)

**If `<SKIP_REVIEW>` is "yes", skip this step and step 6 entirely.**

Capture the diff:
```bash
git diff <DEFAULT_BRANCH>..HEAD
```

Launch 2-3 review sub-agents **in parallel**. Each returns a JSON array of findings.

**Finding format:**
```json
[{"file": "path", "line": 42, "severity": "error|warning", "description": "..."}]
```

**Reviewer 1 — Correctness & Security (model: sonnet):**
```
Review this PR diff for correctness and security. Return ONLY a JSON array of findings.

Review focus:
- Logic errors, missing error handling, incorrect conditionals
- Security: injection, auth bypass, missing tenant scoping, exposed secrets
- Spec compliance: does the code satisfy every acceptance criterion from the issue?
- Dead code: new modules never called from anywhere
- Only report issues that MUST be fixed before merging

Issue spec: <ISSUE_TITLE> — <acceptance criteria section>
Diff:
<diff>
```

**Reviewer 2 — Testing & Quality (model: haiku):**
Only launch if the diff contains test files OR adds new public API surface.
```
Review test quality and coverage. Return ONLY a JSON array of findings.

Review focus:
- Tests that don't assert anything meaningful
- Missing tests for new public functions/endpoints
- Over-mocking that makes tests meaningless
- Missing edge case coverage for critical paths

Diff:
<diff>
```

**Reviewer 3 — Spec Compliance (model: sonnet):**
Only launch if the issue body has structured sections (Acceptance Criteria, Files to Create, etc.).
```
Verify spec compliance. Return ONLY a JSON array of findings.

For each spec section, verify:
- Files to Create: exist with required functionality?
- Files to Modify: specified changes made?
- Acceptance Criteria: each satisfied by code?
- Integration Points: new modules called from specified sites?
- Test Scenarios: test exists for each?

Issue spec:
<ISSUE_BODY>
Diff:
<diff>
```

### 6. Review Fix Loop

Collect findings. If any have `severity: "error"`:

1. Spawn a **sonnet** sub-agent to fix all errors:
   ```
   Fix these code review findings on branch <branch_name>.

   MUST FIX (errors):
   <list error findings>

   FIX IF EASY (warnings):
   <list warning findings>

   After fixing, run: <QUALITY_CMD>
   Commit with: fix(<scope>): address review feedback [#<ISSUE_NUMBER>]
   ```

2. Re-run reviewers (max 3 review cycles total).
3. If errors persist after 3 cycles, escalate with reason "review errors persist after 3 cycles".

If only warnings or no findings, proceed.

### 7. Create PR

```bash
git push -u origin <branch>
```

Extract acceptance criteria from the issue body for the PR description:

```bash
gh pr create --title "<type>: <issue-title> [#<ISSUE_NUMBER>]" --body "$(cat <<'PREOF'
## Summary
Implements #<ISSUE_NUMBER>

## Acceptance Criteria
<extracted from issue>

## Agent Notes
- Quality gate: passed
- Local review: passed (<N> cycles)
- Review findings addressed: <count>
PREOF
)"
```

If CLAUDE.md references a GitHub Project board with status field IDs, move the issue to "In Review".

### 8. Monitor CI

Poll CI status every 60 seconds for up to 30 minutes:

```bash
gh pr checks <pr-number> --json name,state,conclusion
```

Ignore any checks named `Claude Code Review` or `claude-review`.

- All pass → proceed to step 10.
- Any fail → proceed to step 9.
- Timeout (30 min) → escalate with reason "CI timeout".

### 9. Fix CI Failures (max 3 attempts)

1. Get failure details:
   ```bash
   gh run view <run-id> --log-failed 2>/dev/null | tail -100
   ```

2. Spawn a **sonnet** sub-agent to diagnose and fix. It must run `<QUALITY_CMD>` locally and commit the fix.

3. Push: `git push`

4. Go back to step 8. After 3 failed CI fix attempts, escalate with reason "CI failures persist after 3 fix attempts".

### 10. Merge

**Check for merge conflicts first:**
```bash
gh pr view <pr-number> --json mergeable -q .mergeable
```

If `CONFLICTING` (max 2 attempts, then escalate):
1. `git fetch origin <DEFAULT_BRANCH> && git rebase origin/<DEFAULT_BRANCH>`
2. If conflicts, spawn a sonnet sub-agent to resolve them:
   - Resolve all conflicted files and `git add` each one
   - Run `git rebase --continue`
   - Run `<QUALITY_CMD>` to verify nothing is broken
   - If quality fails, fix and amend the commit
3. `git push --force-with-lease`
4. Go back to step 8 (CI re-run)

**Merge:**
```bash
gh pr merge <pr-number> --squash
```

If that fails, try auto-merge:
```bash
gh pr merge <pr-number> --squash --auto
```

Poll every 30 seconds (up to 10 min) until `gh pr view <pr-number> --json state -q .state` returns `MERGED`.

- `MERGED` → continue to cleanup
- `CLOSED` → escalate with reason "PR closed externally"
- Still `OPEN` after 10 min → escalate with reason "merge timeout"

**CRITICAL: Do NOT close the issue until PR state is `MERGED`.**

### 11. Cleanup

```bash
gh issue close <ISSUE_NUMBER>
```

If project board is configured, move to "Done". Remove `agent-working` label if present.

```bash
git checkout <DEFAULT_BRANCH> && git pull origin <DEFAULT_BRANCH>
git branch -d <branch>
```

**Release the lock branch:**
```bash
bash ~/.claude/skills/agent-loop/release.sh <ISSUE_NUMBER>
```

Print: `RESULT:MERGED <pr-url>`

## Escalation

When escalating:
1. Add `needs-human-review` label to the issue
2. Remove `agent-working` label
3. If project board configured, move to "Needs a Human"
4. Comment on the issue explaining what went wrong
5. **Release the lock branch:**
   ```bash
   bash ~/.claude/skills/agent-loop/release.sh <ISSUE_NUMBER>
   ```
6. Print: `RESULT:ESCALATED <reason>`

## Error Handling

| Situation | Action |
|-----------|--------|
| Implementation sub-agent fails | Check if transient (see below); otherwise escalate: "implementation failed" |
| Quality gate fails after retries | Escalate: "quality gate failed after retries" |
| Review errors persist 3 cycles | Escalate: "review errors persist after 3 cycles" |
| CI fails after 3 fix attempts | Escalate: "CI failures persist after 3 fix attempts" |
| Dependency not closed | Add `waiting-on-dependency`, remove `agent-working`, RESULT:BLOCKED |
| Merge conflicts unresolvable | Escalate: "merge conflict resolution failed" |
| PR already exists for issue | Escalate: "PR already exists for this issue" |
| GitHub API error | Retry once, then escalate |

### Transient Error Retry

Before escalating on implementation or API failures, check if the error is transient:
- Rate limit / 429 errors
- Connection reset / timeout
- Provider overload / 529 errors
- "context window exceeded" or token limit errors

If transient:
1. Remove `agent-working` label
2. Re-add the target label (default: `ready-for-agent`)
3. Release the lock branch: `bash ~/.claude/skills/agent-loop/release.sh <ISSUE_NUMBER>`
4. Comment on the issue: "Transient error: <reason>. Re-queued for retry."
5. Print `RESULT:RETRY <reason>` and stop (the next poll cycle will pick it up again)

Do NOT retry more than 2 times for the same issue. Check the issue comments for prior "Transient error" messages — if 2 or more exist, escalate instead of retrying.
````
