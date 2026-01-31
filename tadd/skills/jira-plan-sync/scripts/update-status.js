#!/usr/bin/env node

const https = require('https');

// Check arguments
if (process.argv.length < 4) {
  console.error('Usage: update-status.js <issue-key> <target-status>');
  console.error('  target-status: \'To Do\', \'In Progress\', or \'Done\'');
  process.exit(1);
}

const issueKey = process.argv[2];
const targetStatus = process.argv[3];

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

async function updateStatus() {
  try {
    // Get available transitions
    const transitionsUrl = new URL(`${JIRA_URL}/rest/api/3/issue/${issueKey}/transitions`);
    const transitionsOptions = {
      hostname: transitionsUrl.hostname,
      port: 443,
      path: transitionsUrl.pathname,
      method: 'GET',
      headers: {
        'Authorization': `Basic ${auth}`
      }
    };

    const { statusCode: transStatusCode, data: transData } = await makeRequest(transitionsOptions);

    if (transStatusCode < 200 || transStatusCode >= 300) {
      console.error(`Error fetching transitions (HTTP ${transStatusCode})`);
      process.exit(1);
    }

    const transitions = JSON.parse(transData);
    const transition = transitions.transitions.find(t => t.to.name === targetStatus);

    if (!transition) {
      console.error(`Error: No transition found to status '${targetStatus}'`);
      console.error('Available transitions:');
      transitions.transitions.forEach(t => {
        console.error(`${t.id}: ${t.name} -> ${t.to.name}`);
      });
      process.exit(1);
    }

    // Execute transition
    const transitionUrl = new URL(`${JIRA_URL}/rest/api/3/issue/${issueKey}/transitions`);
    const postData = JSON.stringify({
      transition: { id: transition.id }
    });

    const transitionOptions = {
      hostname: transitionUrl.hostname,
      port: 443,
      path: transitionUrl.pathname,
      method: 'POST',
      headers: {
        'Authorization': `Basic ${auth}`,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(postData)
      }
    };

    const { statusCode: execStatusCode, data: execData } = await makeRequest(transitionOptions, postData);

    if (execStatusCode >= 200 && execStatusCode < 300) {
      console.log(`Successfully transitioned ${issueKey} to '${targetStatus}'`);

      // Clear resolution if moving to an active state (To Do or In Progress)
      if (targetStatus === 'To Do' || targetStatus === 'In Progress' || targetStatus === 'Selected for Development') {
        const clearUrl = new URL(`${JIRA_URL}/rest/api/3/issue/${issueKey}`);
        const clearData = JSON.stringify({
          fields: {
            resolution: null
          }
        });

        const clearOptions = {
          hostname: clearUrl.hostname,
          port: 443,
          path: clearUrl.pathname,
          method: 'PUT',
          headers: {
            'Authorization': `Basic ${auth}`,
            'Content-Type': 'application/json',
            'Content-Length': Buffer.byteLength(clearData)
          }
        };

        const { statusCode: clearStatusCode } = await makeRequest(clearOptions, clearData);

        if (clearStatusCode >= 200 && clearStatusCode < 300) {
          console.log(`Cleared resolution for ${issueKey}`);
        } else {
          console.error(`Warning: Failed to clear resolution (HTTP ${clearStatusCode})`);
        }
      }
    } else {
      console.error(`Error updating status (HTTP ${execStatusCode}):`);
      try {
        const error = JSON.parse(execData);
        console.error(JSON.stringify(error, null, 2));
      } catch (e) {
        console.error(execData);
      }
      process.exit(1);
    }
  } catch (error) {
    console.error('Request failed:', error.message);
    process.exit(1);
  }
}

updateStatus();
