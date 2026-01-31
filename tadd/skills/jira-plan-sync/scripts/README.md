# Jira Plan Sync Scripts

Helper scripts for syncing plan files to Jira. Creates child work items (Tasks) under an epic.

## Requirements

- Node.js (uses built-in `https` module, no external dependencies required)

## Environment Variables Required
```bash
export JIRA_URL="https://your-org.atlassian.net"
export JIRA_EMAIL="your-email@example.com"
export JIRA_API_TOKEN="your-api-token"
export JIRA_PROJECT_KEY="PLT"  # Required - the Jira project key (e.g., PLT, BUILD)
```

Get your API token: https://id.atlassian.com/manage-profile/security/api-tokens

## Scripts

- `create-epic.js` - Create a new Jira epic
- `fetch-subtasks.js` - Fetch all child work items for an epic
- `create-subtask.js` - Create a new child work item (Task) under an epic
- `update-summary.js` - Update the summary (title) of an existing issue
- `update-status.js` - Update the status of a child work item (also clears resolution for active statuses)
- `close-subtask.js` - Close a child work item, remove epic link, and add a comment
- `get-transitions.js` - Get available transitions for an issue

## Usage Examples
```bash
# Create epic
node create-epic.js "Secure Fields Implementation"
# Output: BUILD-123

# Fetch child work items
node fetch-subtasks.js BUILD-123
# Output: JSON with all child work items

# Create child work item
node create-subtask.js BUILD-123 1 "Foundation - Dependencies" "secure-fields"
# Output: JSON with created issue

# Get transitions
node get-transitions.js BUILD-124
# Output: JSON with available transitions

# Update summary (title)
node update-summary.js BUILD-124 "PR1: Foundation - Dependencies and MongoDB"
# Output: Updated: BUILD-124

# Update status (automatically clears resolution if moving to active state)
node update-status.js BUILD-124 "In Progress"
# Output: Success or error message
# Note: When moving to "To Do" or "In Progress", the resolution field is automatically cleared

# Close child work item (removes epic link and closes issue)
node close-subtask.js BUILD-124 "Removed from plan on 2025-01-15"
# Output: Success or error message
# Note: This removes the parent link (disconnects from epic) before closing
```
