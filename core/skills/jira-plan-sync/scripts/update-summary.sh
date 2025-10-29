#!/bin/bash

# Update the summary (title) of a Jira issue
# Usage: ./update-summary.sh ISSUE-KEY "New Summary"

set -e

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 ISSUE-KEY \"New Summary\""
  exit 1
fi

ISSUE_KEY="$1"
NEW_SUMMARY="$2"

# Validate required environment variables
if [ -z "$JIRA_URL" ] || [ -z "$JIRA_EMAIL" ] || [ -z "$JIRA_API_TOKEN" ]; then
  echo "Error: Missing required environment variables"
  echo "Required: JIRA_URL, JIRA_EMAIL, JIRA_API_TOKEN"
  exit 1
fi

# Create netrc file for authentication
NETRC_FILE=$(mktemp)
trap "rm -f $NETRC_FILE" EXIT

cat > "$NETRC_FILE" <<EOF
machine ${JIRA_URL#https://}
login $JIRA_EMAIL
password $JIRA_API_TOKEN
EOF

chmod 600 "$NETRC_FILE"

# Update the issue summary
curl -s --netrc-file "$NETRC_FILE" \
  -X PUT \
  -H "Content-Type: application/json" \
  "${JIRA_URL}/rest/api/3/issue/${ISSUE_KEY}" \
  -d "{
    \"fields\": {
      \"summary\": \"${NEW_SUMMARY}\"
    }
  }" > /dev/null

# Check if update was successful by fetching the issue
RESPONSE=$(curl -s --netrc-file "$NETRC_FILE" \
  -H "Accept: application/json" \
  "${JIRA_URL}/rest/api/3/issue/${ISSUE_KEY}?fields=summary")

# Extract and verify the summary was updated
UPDATED_SUMMARY=$(echo "$RESPONSE" | grep -o '"summary":"[^"]*"' | cut -d'"' -f4)

if [ "$UPDATED_SUMMARY" = "$NEW_SUMMARY" ]; then
  echo "Updated: $ISSUE_KEY"
else
  echo "Error: Failed to update $ISSUE_KEY"
  exit 1
fi
