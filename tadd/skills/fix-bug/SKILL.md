---
description: Find, reproduce, fix, and ship a bug from Jira
---

# Bug Fix Workflow

End-to-end bug fixing workflow using subagents to manage context efficiently.

**Core Invariant**: A bug is NOT selected until it has been reproduced and a failing test exists. Jira assignment and status changes happen ONLY after reproduction is confirmed.

## Architecture

This skill uses **subagents** to isolate each phase, keeping context lean:

| Phase                       | Model  | Why Subagent?                                                                     |
| --------------------------- | ------ | --------------------------------------------------------------------------------- |
| Bug Discovery               | haiku  | Evaluates many bugs, returns only top candidate                                   |
| Reproduction & Failing Test | sonnet | Needs strong reasoning for code analysis + Playwright; verbose snapshots isolated |
| PR Monitoring               | haiku  | Repeated polling; discard intermediate states                                     |

The main agent orchestrates phases and handles user interaction.

---

## Phase 1: Bug Discovery (Subagent)

Spawn a **haiku** subagent to find and evaluate bugs:

```
Task(
  subagent_type: "general-purpose",
  model: "haiku",
  description: "Find fixable bug from Jira",
  prompt: <see Bug Discovery Prompt below>
)
```

### Bug Discovery Prompt

```
You are evaluating bugs from Jira to find one that can be confidently reproduced and fixed.

## Step 1: Query Bugs

Use mcp__atlassian__jira_search:
- jql: "project = PLT AND issuetype = Bug AND status = 'BUGS TO DO' ORDER BY priority DESC, created ASC"
- fields: "summary,description,priority,created,reporter,labels,components"
- limit: 15

## Step 2: Deep Evaluation of Each Bug

For each bug, perform a thorough assessment:

**Reproducibility** (High/Medium/Low):
- Are there EXPLICIT step-by-step reproduction instructions?
- Can the bug be triggered via UI (Playwright), GraphQL query, or API request?
- Are the affected components clearly identifiable?
- Is the environment/context well-specified (which page, which form, which user role)?
- Would you know EXACTLY what to click/type/navigate to reproduce this?

**Fix Confidence** (High/Medium/Low):
- Is the root cause obvious or strongly implied by the description?
- Is the fix isolated to a single service?
- Is it in a well-understood area (forms, workflows, auth, UI rendering)?
- Are there clear before/after expected behaviors described?

**Testability** (High/Medium/Low):
- Can this bug be captured in a unit or integration test?
- Is the expected vs actual behavior clearly defined?
- Are the inputs and outputs deterministic?

IMPORTANT: Only recommend a bug where ALL THREE scores are High. Be brutally honest —
if reproduction steps are vague, score Reproducibility as Medium or Low even if the bug
sounds simple. The #1 priority is that we can DEFINITELY reproduce this bug.

## Step 3: Return Top Candidate

Return ONLY this structured result for the best candidate where ALL THREE scores are High:

```

BUG_KEY: PLT-XXXX
SUMMARY: <title>
DESCRIPTION: <full description from Jira, preserve details>
REPRODUCIBILITY: High - <detailed reason with specific steps you'd follow>
FIX_CONFIDENCE: High - <one sentence reason>
TESTABILITY: High - <what kind of test would capture this, and what assertion>
SERVICE: <platform|builder-ui|identity|forms-api|workflows-api>
REPRODUCTION_STRATEGY: <Playwright UI test|GraphQL query|API request|unit test setup>
PROPOSED_TEST_APPROACH: <1-2 sentences on how you'd write a failing test>
JIRA_URL: https://kualico.atlassian.net/browse/PLT-XXXX

```

If no bugs have High confidence for all three, return the best available with honest
assessments. If the best candidate has Medium on any dimension, explain the risk clearly.
Return "NO_SUITABLE_BUGS" if the backlog is empty or all bugs are too complex/vague.
```

### After Subagent Returns

Parse the result and present to user with `AskUserQuestion`:

```
AskUserQuestion(
  questions: [{
    question: "I found a bug candidate. Should I attempt to reproduce it and write a failing test?",
    header: "Bug Review",
    options: [
      { label: "Attempt reproduction", description: "Try to reproduce and create a failing test before committing" },
      { label: "Keep looking", description: "Search for another bug" }
    ],
    multiSelect: false
  }]
)
```

Include the subagent's full structured output in your message before the question. Be transparent about any Medium scores or risks.

If "Keep looking" → re-run the subagent (pass previously seen bug keys to skip them).
If "Attempt reproduction" → continue to Phase 2.

---

## Phase 2: Branch Setup (Main Agent)

Set up a branch so the failing test can be committed. **Do NOT update Jira yet.**

### Step 2.1: Branch Setup (Parallel Git Operations)

Run these **in parallel**:

```bash
# Fetch latest
git -C <service-path> fetch origin

# Check current branch status
git -C <service-path> branch --show-current
```

Then sequentially:

```bash
git -C <service-path> checkout main
git -C <service-path> pull origin main
git -C <service-path> checkout -b fix/<bug_key>-<short-desc>
```

**CHECKPOINT**: Branch created successfully. Jira is NOT updated yet.

---

## Phase 3: Reproduce Bug & Create Failing Test (GATE)

This is the critical gate. The bug MUST be reproduced AND a failing test MUST be created before proceeding. If either fails, STOP.

### Step 3.1: Bug Reproduction (Subagent)

Spawn a **sonnet** subagent to reproduce the bug. This isolates Playwright's verbose snapshots.

```
Task(
  subagent_type: "general-purpose",
  model: "sonnet",
  description: "Reproduce bug PLT-XXXX",
  prompt: <see Reproduction Prompt below>
)
```

#### Reproduction Prompt

```
You are reproducing a bug using Playwright browser automation.

## Bug Details
KEY: <bug_key>
SUMMARY: <summary>
DESCRIPTION: <full description>
REPRODUCTION_STRATEGY: <strategy from Phase 1>

## Context Management (IMPORTANT)
- Take ONE initial snapshot to orient, then minimize snapshots
- Use predictable element names (button "Save", textbox "Name") over refs when possible
- Skip snapshots on complex pages (icon pickers, data grids)
- Chain predictable actions without intermediate snapshots

## Login (if needed)
1. Navigate: http://local.kualibuild.com:52000/authn/kuali
2. Credentials: kualiadmin / admin
3. Click "Sign In"
4. Certificate error: Click "Advanced" → "Proceed to local.kualibuild.com (unsafe)"
5. Re-enter credentials on HTTPS page

## Your Task
1. Navigate to the affected area
2. Follow reproduction steps from the bug description
3. Capture the error state (screenshot if visual, console logs if JS error)
4. Document exact reproduction steps
5. Identify the specific code area responsible

## Return Format
```

STATUS: REPRODUCED | NOT_REPRODUCED | PARTIAL
STEPS:

1. <step>
2. <step>
   ...
   ERROR_OBSERVED: <what went wrong>
   SCREENSHOT: <filename if taken>
   AFFECTED_CODE_AREA: <your best guess at which files/components are involved>
   NOTES: <any additional observations>

```

If NOT_REPRODUCED, explain what you tried and what happened instead.
```

#### After Reproduction Subagent Returns

- If **NOT_REPRODUCED** → **HARD STOP**. Do NOT proceed. Clean up the branch, add a Jira comment explaining what was tried and what happened instead, and ask user whether to investigate further or pick another bug.
- If **PARTIAL** → Ask user whether the partial reproduction is sufficient to write a test, or whether to pick another bug.
- If **REPRODUCED** → Continue to Step 3.2.

### Step 3.2: Write Failing Test (Main Agent)

This phase requires code understanding — run in main agent for better reasoning.

#### Identify Test Location

| Service       | Test Location        | Command                        |
| ------------- | -------------------- | ------------------------------ |
| builder-ui    | `src/**/*.test.tsx`  | `pnpm test -- --run <file>`    |
| platform      | `test/**/*_test.exs` | `mix test <file>`              |
| identity      | `test/**/*.test.js`  | `pnpm test -- --grep "<name>"` |
| forms-api     | `test/**/*.test.js`  | `pnpm test -- --grep "<name>"` |
| workflows-api | `src/**/*.test.js`   | `pnpm test -- --grep "<name>"` |

#### Write the Failing Test

Create test(s) that:

1. Set up preconditions matching the reproduction scenario
2. Execute the buggy action
3. Assert EXPECTED (correct) behavior — the test MUST fail because the bug exists

#### Verify Test Fails

Run the test — it **MUST fail** with an error related to the bug.

- If the test **passes** (bug not captured) → rethink the test approach. Try a different angle. If after two attempts the bug cannot be captured in a test, **HARD STOP** and ask user how to proceed.
- If the test **fails for unrelated reasons** (setup issues, missing deps) → fix the test setup and retry.
- If the test **fails with bug-related error** → **GATE PASSED**. Continue to Phase 4.

**CHECKPOINT**: Bug reproduced AND failing test exists. Gate passed.

---

## Phase 4: Jira Assignment (Main Agent)

**Only reach this phase after Phase 3 gate is passed.**

### Step 4.1: Update Jira (Parallel)

Run these two calls **in parallel**:

```
# Call 1: Assign to user
mcp__atlassian__jira_update_issue(
  issue_key: "<bug_key>",
  fields: { "assignee": "tadd@kuali.co" }
)

# Call 2: Get transitions (to find IN PROGRESS id)
mcp__atlassian__jira_get_transitions(issue_key: "<bug_key>")
```

Then transition to IN PROGRESS:

```
mcp__atlassian__jira_transition_issue(
  issue_key: "<bug_key>",
  transition_id: "<in_progress_id>"
)
```

**CHECKPOINT**: Bug is now assigned and In Progress. We have a reproduction and a failing test.

---

## Phase 5: Bug Fix (Main Agent)

### Step 5.1: Implement Fix

Minimal, focused fix. Follow service code style.

### Step 5.2: Verify Fix (Parallel Test Runs)

If multiple test suites are affected, run them **in parallel**:

```bash
# Example: run unit tests and lint in parallel
cd <service> && pnpm test &
cd <service> && pnpm lint &
wait
```

Or use separate Bash calls with `run_in_background: true`, then collect results.

### Step 5.3: Manual Verification (Subagent)

Optional: spawn haiku subagent to re-run reproduction steps and confirm fix works in the browser.

**CHECKPOINT**: All tests pass (including the previously-failing test), manual verification succeeds.

---

## Phase 6: PR Submission & Monitoring

### Step 6.1: Commit and Push

```bash
git -C <service-path> add <files>
git -C <service-path> commit -m "$(cat <<'EOF'
fix(<area>): <description>

Fixes PLT-XXXX
EOF
)"
git -C <service-path> push -u origin fix/<bug_key>-<short-desc>
```

### Step 6.2: Create PR

```bash
cd <service-path> && gh pr create \
  --title "fix(<area>): <description>" \
  --body "$(cat <<'EOF'
## Summary
<1-2 sentences>

Fixes PLT-XXXX

**Spec**: https://kualico.atlassian.net/browse/PLT-XXXX
EOF
)" \
  --label "change_type/application"
```

### Step 6.3: PR Monitoring Loop (Subagent)

For ongoing monitoring, spawn a **haiku** subagent that polls and reports:

```
Task(
  subagent_type: "general-purpose",
  model: "haiku",
  description: "Monitor PR status",
  prompt: <see Monitoring Prompt below>
)
```

### Monitoring Prompt

```
You are monitoring a PR until it's ready for human review.

PR_URL: <url>
SERVICE_PATH: <path>
BUG_KEY: <key>

## Check These Three Things (IN PARALLEL)

Run all three checks in a single response with parallel tool calls:

1. CI Status: `cd <service-path> && gh pr checks`
2. Review Comments: `cd <service-path> && gh pr view --comments`
3. Branch Sync: `git -C <service-path> fetch origin && git -C <service-path> log HEAD..origin/main --oneline`

## Evaluate Results

**CI Status**:
- All passing → CI_OK
- Any failing → CI_FAIL: <which check>
- Pending → CI_PENDING

**Review Comments**:
- No unresolved comments → REVIEWS_OK
- Has unresolved comments → REVIEWS_NEED_ACTION: <summary of feedback>

**Branch Sync**:
- No commits behind → SYNC_OK
- Commits behind → SYNC_NEEDED: <number> commits behind

## Return Format

```

CI: <CI_OK|CI_FAIL|CI_PENDING> [details if not OK]
REVIEWS: <REVIEWS_OK|REVIEWS_NEED_ACTION> [summary if action needed]
SYNC: <SYNC_OK|SYNC_NEEDED> [count if needed]
READY_FOR_HUMAN: <YES|NO>
ACTION_NEEDED: <description of what to do next, or "None">

```

```

### After Monitoring Subagent Returns

Based on result:

| Status               | Action                                                        |
| -------------------- | ------------------------------------------------------------- |
| CI_FAIL              | Fix the failing test/lint, commit, push, re-monitor           |
| REVIEWS_NEED_ACTION  | Address feedback, commit, push, reply to comments, re-monitor |
| SYNC_NEEDED          | Rebase on main, force-push, re-monitor                        |
| READY_FOR_HUMAN: YES | Declare done                                                  |

For fixes, work in main agent (needs code context), then re-spawn monitoring subagent.

### Step 6.4: Declare Done

When monitoring returns `READY_FOR_HUMAN: YES`:

```
## Bug Fix Complete

**Bug**: PLT-XXXX - <summary>
**PR**: <url>

### What was fixed
<1-2 sentences>

### Tests added
- <test description>

Ready for human review and merge.
```

---

## Error Recovery

| Situation                      | Action                                                                                              |
| ------------------------------ | --------------------------------------------------------------------------------------------------- |
| Bug can't be reproduced        | **HARD STOP**. Add Jira comment with what was tried. Delete branch. Ask user to pick another.       |
| Failing test can't be written  | **HARD STOP**. Add Jira comment explaining the difficulty. Delete branch. Ask user to pick another. |
| CI keeps failing on unrelated  | Ask user if they want to investigate or wait                                                        |
| Major review changes requested | Explain scope, ask user before proceeding                                                           |
| Merge conflicts during rebase  | Resolve conflicts, run tests, push                                                                  |

---

## Flow Summary

```
Discovery → Dev Confirmation → Branch → Reproduce → Failing Test
                                                         │
                                              ┌──────────┴──────────┐
                                              │                     │
                                           PASSED               FAILED
                                              │                     │
                                     Assign Jira +          HARD STOP
                                     Move In Progress       Clean up branch
                                              │              Comment on Jira
                                           Fix Bug           Ask user
                                              │
                                           PR + Monitor
```

---

$ARGUMENTS
