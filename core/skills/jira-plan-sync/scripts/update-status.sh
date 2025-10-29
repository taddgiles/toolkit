#!/bin/bash
set -euo pipefail

# Update the status of a Jira issue and handle resolution field
# When moving to "To Do" or "In Progress", clears the resolution
# When moving to "Done", the transition typically sets the resolution

# Check arguments
if [ $# -lt 2 ]; then
  echo "Usage: $0 <issue-key> <target-status>" >&2
  echo "  target-status: 'To Do', 'In Progress', or 'Done'" >&2
  exit 1
fi

ISSUE_KEY="$1"
TARGET_STATUS="$2"

# Check environment variables
if [ -z "${JIRA_URL:-}" ] || [ -z "${JIRA_EMAIL:-}" ] || [ -z "${JIRA_API_TOKEN:-}" ]; then
  echo "Error: Missing required environment variables (JIRA_URL, JIRA_EMAIL, JIRA_API_TOKEN)" >&2
  exit 1
fi

AUTH=$(echo -n "${JIRA_EMAIL}:${JIRA_API_TOKEN}" | base64)

# Get available transitions
TRANSITIONS=$(curl -s -X GET "${JIRA_URL}/rest/api/3/issue/${ISSUE_KEY}/transitions" \
  -H "Authorization: Basic ${AUTH}")

# Find transition ID for target status
TRANSITION_ID=$(echo "$TRANSITIONS" | jq -r '.transitions[] | select(.to.name == "'"${TARGET_STATUS}"'") | .id' | head -n1)

if [ -z "$TRANSITION_ID" ]; then
  echo "Error: No transition found to status '${TARGET_STATUS}'" >&2
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
  echo "Successfully transitioned ${ISSUE_KEY} to '${TARGET_STATUS}'"

  # Clear resolution if moving to an active state (To Do or In Progress)
  if [[ "$TARGET_STATUS" == "To Do" || "$TARGET_STATUS" == "In Progress" || "$TARGET_STATUS" == "Selected for Development" ]]; then
    CLEAR_RESOLUTION=$(curl -s -w "\n%{http_code}" -X PUT "${JIRA_URL}/rest/api/3/issue/${ISSUE_KEY}" \
      -H "Authorization: Basic ${AUTH}" \
      -H "Content-Type: application/json" \
      -d '{
        "fields": {
          "resolution": null
        }
      }')

    HTTP_CODE_RES=$(echo "$CLEAR_RESOLUTION" | tail -n1)
    if [ "$HTTP_CODE_RES" -ge 200 ] && [ "$HTTP_CODE_RES" -lt 300 ]; then
      echo "Cleared resolution for ${ISSUE_KEY}"
    else
      echo "Warning: Failed to clear resolution (HTTP $HTTP_CODE_RES)" >&2
    fi
  fi
else
  echo "Error updating status (HTTP $HTTP_CODE):" >&2
  echo "$BODY" | jq '.' >&2
  exit 1
fi
