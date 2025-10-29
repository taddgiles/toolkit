#!/bin/bash
set -euo pipefail

# Check arguments
if [ $# -lt 4 ]; then
  echo "Usage: $0 <epic-key> <pr-number> <title> <label> [description]" >&2
  exit 1
fi

EPIC_KEY="$1"
PR_NUMBER="$2"
TITLE="$3"
LABEL="$4"
DESCRIPTION="${5:-}"

# Check environment variables
if [ -z "${JIRA_URL:-}" ] || [ -z "${JIRA_EMAIL:-}" ] || [ -z "${JIRA_API_TOKEN:-}" ] || [ -z "${JIRA_PROJECT_KEY:-}" ]; then
  echo "Error: Missing required environment variables (JIRA_URL, JIRA_EMAIL, JIRA_API_TOKEN, JIRA_PROJECT_KEY)" >&2
  exit 1
fi

PROJECT_KEY="${JIRA_PROJECT_KEY}"
AUTH=$(echo -n "${JIRA_EMAIL}:${JIRA_API_TOKEN}" | base64)

# Create child work item (Task linked to Epic)
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${JIRA_URL}/rest/api/3/issue" \
  -H "Authorization: Basic ${AUTH}" \
  -H "Content-Type: application/json" \
  -d '{
    "fields": {
      "project": {"key": "'"${PROJECT_KEY}"'"},
      "parent": {"key": "'"${EPIC_KEY}"'"},
      "summary": "PR'"${PR_NUMBER}"': '"${TITLE}"'",
      "description": {
        "type": "doc",
        "version": 1,
        "content": [
          {
            "type": "paragraph",
            "content": [
              {
                "type": "text",
                "text": "'"${DESCRIPTION}"'"
              }
            ]
          }
        ]
      },
      "issuetype": {"name": "Task"},
      "labels": ["'"${LABEL}"'"]
    }
  }')

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
  echo "$BODY" | jq -r '.key'
else
  echo "Error creating child work item (HTTP $HTTP_CODE):" >&2
  echo "$BODY" | jq -r '.errorMessages[]?, .errors | to_entries[] | "\(.key): \(.value)"' >&2
  exit 1
fi
