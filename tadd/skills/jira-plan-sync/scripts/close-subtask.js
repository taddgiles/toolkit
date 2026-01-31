#!/usr/bin/env node

const https = require('https');

// Check arguments
if (process.argv.length < 4) {
  console.error('Usage: close-subtask.js <issue-key> <comment>');
  process.exit(1);
}

const issueKey = process.argv[2];
const comment = process.argv[3];

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

async function closeSubtask() {
  try {
    // Remove parent link (disconnect from epic)
    const removeParentUrl = new URL(`${JIRA_URL}/rest/api/3/issue/${issueKey}`);
    const removeParentData = JSON.stringify({
      fields: {
        parent: null
      }
    });

    const removeParentOptions = {
      hostname: removeParentUrl.hostname,
      port: 443,
      path: removeParentUrl.pathname,
      method: 'PUT',
      headers: {
        'Authorization': `Basic ${auth}`,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(removeParentData)
      }
    };

    const { statusCode: parentStatusCode } = await makeRequest(removeParentOptions, removeParentData);

    if (parentStatusCode < 200 || parentStatusCode >= 300) {
      console.error(`Warning: Failed to remove parent link (HTTP ${parentStatusCode})`);
    }

    // Add comment
    const commentUrl = new URL(`${JIRA_URL}/rest/api/3/issue/${issueKey}/comment`);
    const commentData = JSON.stringify({
      body: {
        type: 'doc',
        version: 1,
        content: [
          {
            type: 'paragraph',
            content: [
              {
                type: 'text',
                text: comment
              }
            ]
          }
        ]
      }
    });

    const commentOptions = {
      hostname: commentUrl.hostname,
      port: 443,
      path: commentUrl.pathname,
      method: 'POST',
      headers: {
        'Authorization': `Basic ${auth}`,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(commentData)
      }
    };

    const { statusCode: commentStatusCode } = await makeRequest(commentOptions, commentData);

    if (commentStatusCode < 200 || commentStatusCode >= 300) {
      console.error(`Warning: Failed to add comment (HTTP ${commentStatusCode})`);
    }

    // Get transitions to find "Closed" or "Done"
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
    const closeTransition = transitions.transitions.find(t =>
      /Closed|Cancelled|Done/i.test(t.to.name)
    );

    if (!closeTransition) {
      console.error(`Error: No close/done transition found for ${issueKey}`);
      console.error('Available transitions:');
      transitions.transitions.forEach(t => {
        console.error(`${t.id}: ${t.name} -> ${t.to.name}`);
      });
      process.exit(1);
    }

    // Execute transition
    const transitionUrl = new URL(`${JIRA_URL}/rest/api/3/issue/${issueKey}/transitions`);
    const transitionData = JSON.stringify({
      transition: { id: closeTransition.id }
    });

    const transitionOptions = {
      hostname: transitionUrl.hostname,
      port: 443,
      path: transitionUrl.pathname,
      method: 'POST',
      headers: {
        'Authorization': `Basic ${auth}`,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(transitionData)
      }
    };

    const { statusCode: execStatusCode, data: execData } = await makeRequest(transitionOptions, transitionData);

    if (execStatusCode >= 200 && execStatusCode < 300) {
      console.log(`Successfully closed ${issueKey}`);
    } else {
      console.error(`Error closing subtask (HTTP ${execStatusCode}):`);
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

closeSubtask();
