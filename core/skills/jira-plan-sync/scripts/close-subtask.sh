#!/bin/bash
set -euo pipefail

# Close a Jira issue and disconnect it from its parent epic
# This script:
# 1. Removes the parent link (disconnects from epic)
# 2. Adds a comment explaining why it was closed
# 3. Transitions the issue to a closed state

# Check arguments
if [ $# -lt 2 ]; then
  echo "Usage: $0 <issue-key> <comment>" >&2
  exit 1
fi

ISSUE_KEY="$1"
COMMENT="$2"

# Check environment variables
if [ -z "${JIRA_URL:-}" ] || [ -z "${JIRA_EMAIL:-}" ] || [ -z "${JIRA_API_TOKEN:-}" ]; then
  echo "Error: Missing required environment variables (JIRA_URL, JIRA_EMAIL, JIRA_API_TOKEN)" >&2
  exit 1
fi

AUTH=$(echo -n "${JIRA_EMAIL}:${JIRA_API_TOKEN}" | base64)

# Remove parent link (disconnect from epic)
REMOVE_PARENT_RESPONSE=$(curl -s -w "\n%{http_code}" -X PUT "${JIRA_URL}/rest/api/3/issue/${ISSUE_KEY}" \
  -H "Authorization: Basic ${AUTH}" \
  -H "Content-Type: application/json" \
  -d '{
    "fields": {
      "parent": null
    }
  }')

HTTP_CODE_PARENT=$(echo "$REMOVE_PARENT_RESPONSE" | tail -n1)
if [ "$HTTP_CODE_PARENT" -lt 200 ] || [ "$HTTP_CODE_PARENT" -ge 300 ]; then
  echo "Warning: Failed to remove parent link (HTTP $HTTP_CODE_PARENT)" >&2
fi

# Add comment
COMMENT_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${JIRA_URL}/rest/api/3/issue/${ISSUE_KEY}/comment" \
  -H "Authorization: Basic ${AUTH}" \
  -H "Content-Type: application/json" \
  -d '{
    "body": {
      "type": "doc",
      "version": 1,
      "content": [
        {
          "type": "paragraph",
          "content": [
            {
              "type": "text",
              "text": "'"${COMMENT}"'"
            }
          ]
        }
      ]
    }
  }')

HTTP_CODE=$(echo "$COMMENT_RESPONSE" | tail -n1)
if [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
  echo "Warning: Failed to add comment (HTTP $HTTP_CODE)" >&2
fi

# Get transitions to find "Closed" or "Done"
TRANSITIONS=$(curl -s -X GET "${JIRA_URL}/rest/api/3/issue/${ISSUE_KEY}/transitions" \
  -H "Authorization: Basic ${AUTH}")

# Try to find Closed, Cancelled, or Done transition
TRANSITION_ID=$(echo "$TRANSITIONS" | jq -r '.transitions[] | select(.to.name | test("Closed|Cancelled|Done"; "i")) | .id' | head -n1)

if [ -z "$TRANSITION_ID" ]; then
  echo "Error: No close/done transition found for ${ISSUE_KEY}" >&2
  echo "Available transitions:" >&2
  echo "$TRANSITIONS" | jq -r '.transitions[] | "\(.id): \(.name) -> \(.to.name)"' >&2
  exit 1
fi

# Execute transition
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${JIRA_URL}/rest/api/3/issue/${ISSUE_KEY}/transitions" \
  -H "Authorization: Basic ${AUTH}" \
  -H "Content-Type: application/json" \
  -d '{
    "transition": {"id": "'"${TRANSITION_ID}"'"}
  }')

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
  echo "Successfully closed ${ISSUE_KEY}"
else
  echo "Error closing subtask (HTTP $HTTP_CODE):" >&2
  echo "$BODY" | jq '.' >&2
  exit 1
fi
