#!/usr/bin/env node

const https = require('https');

// Check arguments
if (process.argv.length < 3) {
  console.error('Usage: fetch-subtasks.js <epic-key>');
  process.exit(1);
}

const epicKey = process.argv[2];

// Check environment variables
const { JIRA_URL, JIRA_EMAIL, JIRA_API_TOKEN } = process.env;
if (!JIRA_URL || !JIRA_EMAIL || !JIRA_API_TOKEN) {
  console.error('Error: Missing required environment variables (JIRA_URL, JIRA_EMAIL, JIRA_API_TOKEN)');
  process.exit(1);
}

const auth = Buffer.from(`${JIRA_EMAIL}:${JIRA_API_TOKEN}`).toString('base64');
const url = new URL(`${JIRA_URL}/rest/api/3/search/jql`);

const postData = JSON.stringify({
  jql: `parent=${epicKey}`,
  fields: ['summary', 'status', 'key'],
  maxResults: 100
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
      console.log(data);
    } else {
      console.error(`Error fetching subtasks (HTTP ${res.statusCode}):`);
      try {
        const parsed = JSON.parse(data);
        console.error(JSON.stringify(parsed, null, 2));
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
