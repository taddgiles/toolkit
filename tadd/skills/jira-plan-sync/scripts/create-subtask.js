#!/usr/bin/env node

const https = require('https');

// Check arguments
if (process.argv.length < 6) {
  console.error('Usage: create-subtask.js <epic-key> <pr-number> <title> <label> [description]');
  process.exit(1);
}

const epicKey = process.argv[2];
const prNumber = process.argv[3];
const title = process.argv[4];
const label = process.argv[5];
const description = process.argv[6] || '';

// Check environment variables
const { JIRA_URL, JIRA_EMAIL, JIRA_API_TOKEN, JIRA_PROJECT_KEY } = process.env;
if (!JIRA_URL || !JIRA_EMAIL || !JIRA_API_TOKEN || !JIRA_PROJECT_KEY) {
  console.error('Error: Missing required environment variables (JIRA_URL, JIRA_EMAIL, JIRA_API_TOKEN, JIRA_PROJECT_KEY)');
  process.exit(1);
}

const auth = Buffer.from(`${JIRA_EMAIL}:${JIRA_API_TOKEN}`).toString('base64');
const url = new URL(`${JIRA_URL}/rest/api/3/issue`);

const postData = JSON.stringify({
  fields: {
    project: { key: JIRA_PROJECT_KEY },
    parent: { key: epicKey },
    summary: `PR${prNumber}: ${title}`,
    description: {
      type: 'doc',
      version: 1,
      content: [
        {
          type: 'paragraph',
          content: [
            {
              type: 'text',
              text: description
            }
          ]
        }
      ]
    },
    issuetype: { name: 'Task' },
    labels: [label]
  }
});

const options = {
  hostname: url.hostname,
  port: 443,
  path: url.pathname,
  method: 'POST',
  headers: {
    'Authorization': `Basic ${auth}`,
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(postData)
  }
};

const req = https.request(options, (res) => {
  let data = '';

  res.on('data', (chunk) => {
    data += chunk;
  });

  res.on('end', () => {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      const response = JSON.parse(data);
      console.log(response.key);
    } else {
      console.error(`Error creating child work item (HTTP ${res.statusCode}):`);
      try {
        const error = JSON.parse(data);
        if (error.errorMessages) {
          error.errorMessages.forEach(msg => console.error(msg));
        }
        if (error.errors) {
          Object.entries(error.errors).forEach(([key, value]) => {
            console.error(`${key}: ${value}`);
          });
        }
      } catch (e) {
        console.error(data);
      }
      process.exit(1);
    }
  });
});

req.on('error', (error) => {
  console.error('Request failed:', error.message);
  process.exit(1);
});

req.write(postData);
req.end();
