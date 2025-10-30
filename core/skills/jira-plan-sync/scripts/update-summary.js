#!/usr/bin/env node

const https = require('https');

// Check arguments
if (process.argv.length < 4) {
  console.error('Usage: update-summary.js <issue-key> <new-summary>');
  process.exit(1);
}

const issueKey = process.argv[2];
const newSummary = process.argv[3];

// Check environment variables
const { JIRA_URL, JIRA_EMAIL, JIRA_API_TOKEN } = process.env;
if (!JIRA_URL || !JIRA_EMAIL || !JIRA_API_TOKEN) {
  console.error('Error: Missing required environment variables (JIRA_URL, JIRA_EMAIL, JIRA_API_TOKEN)');
  process.exit(1);
}

const auth = Buffer.from(`${JIRA_EMAIL}:${JIRA_API_TOKEN}`).toString('base64');

// Function to make HTTPS request
function makeRequest(options, postData = null) {
  return new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      let data = '';

      res.on('data', (chunk) => {
        data += chunk;
      });

      res.on('end', () => {
        resolve({ statusCode: res.statusCode, data });
      });
    });

    req.on('error', (error) => {
      reject(error);
    });

    if (postData) {
      req.write(postData);
    }
    req.end();
  });
}

async function updateSummary() {
  // Update the issue summary
  const url = new URL(`${JIRA_URL}/rest/api/3/issue/${issueKey}`);
  const putData = JSON.stringify({
    fields: {
      summary: newSummary
    }
  });

  const putOptions = {
    hostname: url.hostname,
    port: 443,
    path: url.pathname,
    method: 'PUT',
    headers: {
      'Authorization': `Basic ${auth}`,
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(putData)
    }
  };

  try {
    await makeRequest(putOptions, putData);

    // Verify the update by fetching the issue
    const getUrl = new URL(`${JIRA_URL}/rest/api/3/issue/${issueKey}?fields=summary`);
    const getOptions = {
      hostname: getUrl.hostname,
      port: 443,
      path: getUrl.pathname + getUrl.search,
      method: 'GET',
      headers: {
        'Authorization': `Basic ${auth}`,
        'Accept': 'application/json'
      }
    };

    const { statusCode, data } = await makeRequest(getOptions);

    if (statusCode >= 200 && statusCode < 300) {
      const response = JSON.parse(data);
      const updatedSummary = response.fields.summary;

      if (updatedSummary === newSummary) {
        console.log(`Updated: ${issueKey}`);
      } else {
        console.error(`Error: Failed to update ${issueKey}`);
        process.exit(1);
      }
    } else {
      console.error(`Error: Failed to verify update (HTTP ${statusCode})`);
      process.exit(1);
    }
  } catch (error) {
    console.error('Request failed:', error.message);
    process.exit(1);
  }
}

updateSummary();
