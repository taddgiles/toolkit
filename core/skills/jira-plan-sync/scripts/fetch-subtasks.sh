#!/bin/bash
set -euo pipefail

# Check arguments
if [ $# -lt 1 ]; then
  echo "Usage: $0 <epic-key>" >&2
  exit 1
fi

EPIC_KEY="$1"

# Check environment variables
if [ -z "${JIRA_URL:-}" ] || [ -z "${JIRA_EMAIL:-}" ] || [ -z "${JIRA_API_TOKEN:-}" ]; then
  echo "Error: Missing required environment variables (JIRA_URL, JIRA_EMAIL, JIRA_API_TOKEN)" >&2
  exit 1
fi

AUTH=$(echo -n "${JIRA_EMAIL}:${JIRA_API_TOKEN}" | base64)

# Fetch subtasks
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${JIRA_URL}/rest/api/3/search/jql" \
  -H "Authorization: Basic ${AUTH}" \
  -H "Content-Type: application/json" \
  -d '{
    "jql": "parent='"${EPIC_KEY}"'",
    "fields": ["summary", "status", "key"],
    "maxResults": 100
  }')

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
  echo "$BODY"
else
  echo "Error fetching subtasks (HTTP $HTTP_CODE):" >&2
  echo "$BODY" | jq '.' >&2
  exit 1
fi
