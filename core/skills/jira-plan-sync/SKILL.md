---
name: Jira Plan Sync
description: Sync plan files from specs/{plan-name}/{plan-name}-plan.md to Jira. Creates/updates/closes subtasks under an epic. Use when user asks to sync a plan to Jira.
---

# Jira Plan Sync

Syncs plan files to Jira by managing child work items (Tasks) under an epic.

## When to Use

- User says "sync [plan-name] to jira"
- User says "update jira with [plan-name] plan"
- User asks to synchronize a plan file with Jira

## Instructions

### 1. Validate Inputs

Check that required environment variables are set:
- JIRA_URL
- JIRA_EMAIL
- JIRA_API_TOKEN
- JIRA_PROJECT_KEY (required - the Jira project key like "PLT" or "BUILD")

Extract plan name from user request (e.g., "secure-fields").

### 2. Read Plan File

Load `specs/{plan-name}/{plan-name}-plan.md`.

If file doesn't exist, list available plans in `specs/` directory and exit.

### 3. Get or Create Epic

Look for epic key in plan file with pattern: `**Jira Epic:** PROJECT-123`

If NOT found:
- Extract plan title (first `#` heading)
- Create epic using script: `./scripts/create-epic.sh "{title}"`
- Add epic key to plan file after title
- Commit change: `git add specs/{plan-name}/{plan-name}-plan.md && git commit -m "Add Jira epic key"`

### 4. Parse PRs from Plan

Find the "PR Status Tracker" section.

Extract all PRs matching pattern: `- [checkbox] PRN: Title... - Status:`

Map checkboxes to Jira statuses:
- `[x]` → "Done"
- `[~]` → "In Progress"
- `[ ]` → "To Do"

Build list of PRs with: number, title, status

### 5. Fetch Existing Child Work Items

Run: `./scripts/fetch-subtasks.sh {epic-key}`

This script returns JSON with existing child work items. Parse the output to extract PR numbers from the summary field.

### 6. Sync Changes

**For each PR in plan:**
- If child work item doesn't exist: `./scripts/create-subtask.sh {epic-key} {pr-number} "{title}" {plan-name}`
- If child work item exists:
  - Compare title: If Jira summary differs from plan title, run `./scripts/update-summary.sh {issue-key} "{title}"`
  - Compare status: If status differs, run `./scripts/update-status.sh {issue-key} "{status}"`
    - Note: When transitioning to "To Do" or "In Progress", the script automatically clears the resolution field
    - This ensures issues moved back from "Done" are properly reopened

**For child work items in Jira but not in plan:**

Compare the list of PRs from Jira (step 5) with the list of PRs from the plan (step 4).

Identify PRs that exist in Jira but are NOT in the current plan file. For each removed PR:
- Call `./scripts/close-subtask.sh {issue-key} "Removed from plan"`
- This script will:
  1. Remove the parent link (disconnect from epic)
  2. Add a comment explaining the removal
  3. Transition the issue to "Closed" or "Done" status

### 7. Report Results

Output summary:
```
Plan: specs/{plan-name}/{plan-name}-plan.md
Epic: {epic-key}
Total PRs: {count}
Created: {count} child work items (PR1, PR5, ...)
Updated titles: {count} child work items (PR2, PR7, ...)
Updated status: {count} child work items (PR8, PR12, ...)
Closed: {count} child work items (PR3, ...)
```

## Helper Scripts

All scripts are in the `scripts/` folder and handle Jira API calls.

See `scripts/README.md` for details on each script.

## Important Constraints

**CRITICAL:** You must ONLY use the bash scripts provided in the `scripts/` folder. Do NOT:
- Create or use Python scripts
- Create or use any inline Python code (e.g., `python3 -c "..."`)
- Use `jq` or other JSON parsing tools inline

Instead:
- Use `grep`, `sed`, `awk` to parse the JSON output from scripts
- Extract PR numbers from summaries using bash text processing
- All logic must be implemented using bash commands and the provided scripts
