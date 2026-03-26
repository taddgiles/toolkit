---
description: "Review a Kuali Platform PR for code quality, security, and testing. Only use this skill when the user explicitly invokes it via /review-platform-pr — never trigger automatically."
---

# PR Review Skill (Kuali Platform)

Cost-optimized PR review for the Kuali Platform multi-service project. Uses 2-3 focused agents instead of 9 to minimize token spend while maintaining review quality.

## Input

```text
$ARGUMENTS
```

If `$ARGUMENTS` is empty or does not contain a GitHub PR URL, ask the user for the PR URL before proceeding.

## Process

### Step 1: Fetch PR Data

Run these in parallel:

```bash
# Get PR metadata
gh pr view {url} --json title,body,baseRefName,headRefName,files

# Get the full diff
gh pr diff {url}

# Get changed file names
gh pr diff {url} --name-only
```

### Step 2: Identify Service and Split the Diff

Determine which service this PR belongs to from the repo name in the URL:

| Repo | Stack |
|------|-------|
| platform | Elixir 1.18, Phoenix 1.7, Absinthe, OTP 28 |
| tenant-manager | Elixir 1.15, Phoenix 1.7, OTP 25 |
| builder-ui | React 18, TypeScript, Vite, Node 22, pnpm |
| identity | Express 4.x, JavaScript ESM, Node 22, pnpm (no lodash) |
| workflows-api | Express 4.x, JavaScript ESM, Node 22, pnpm |

Split the diff into two buckets based on file paths:
- **Source files**: Application code (`.ex`, `.exs`, `.ts`, `.tsx`, `.jsx`, `.js`, `.mjs` — excluding test files)
- **Test files**: Anything in a `test/` or `__tests__/` directory, or files matching `*.test.*`, `*_test.*`, `*.spec.*`

This split lets each agent focus on its area without processing irrelevant files.

### Step 3: Load Project Context (Lightweight)

Read only the minimum context needed — do NOT pass full files to agents. Instead, distill the relevant rules into the agent prompts below (they already contain the key principles).

If the PR's repo has a `CLAUDE.md` at its root, skim it for any service-specific rules not covered below. Only include novel rules in agent context.

### Step 4: Launch Review Agents

Launch **only the applicable agents** in parallel. Each agent returns a JSON array:

```json
[
  {
    "file": "path/to/file.ex",
    "line": 42,
    "severity": "critical|suggestion",
    "comment": "Brief comment"
  }
]
```

- `critical`: A concrete bug, security vulnerability, or data integrity issue that will break in production. Examples: missing tenant scoping, SQL injection, null dereference on a common path, broken accessibility that violates WCAG AA. If you find yourself writing "this is safe in practice" or "this may be intentional", it is NOT critical.
- `suggestion`: Everything else — code style, theoretical concerns, maintenance hazards, patterns that work but could be cleaner, performance improvements. When in doubt, use suggestion.

Empty array `[]` means no issues found.

---

#### Agent A: Code Quality (model: haiku)

This single agent replaces the old Compliance, Language Specialist, Simplicity, and Accessibility agents. It reviews source files only.

The prompt below adapts based on the detected service stack. Use the Elixir variant for platform/tenant-manager, the React/TS variant for builder-ui, and the JS variant for identity/workflows-api.

**For Elixir services (platform, tenant-manager):**

```
You are reviewing an Elixir PR for code quality. Return ONLY a JSON array of issues. No preamble.

Project rules:
- Single-purpose functions with pattern matching for control flow
- Guard clauses for edge cases, pipeline operator for transformations
- {:ok, _} / {:error, _} tuples for error handling
- All data queries MUST be tenant-scoped (multi-tenant app)
- All new endpoints/jobs MUST have OpenTelemetry tracing spans
- No hardcoded user-facing strings (i18n required)
- Comments only explain "why", never "what"
- No over-engineering or premature abstractions

Check for:
- Non-idiomatic Elixir (nested case, missing pattern matching, deep nesting)
- Ecto N+1 queries or missing preloads
- Missing tenant scoping on data access
- Missing tracing/metrics on new endpoints or Oban jobs
- Unnecessary complexity (wrappers, abstractions for one-time use)
- Hardcoded strings that should be internationalized

Diff (source files only):
{source_diff}
```

**For React/TypeScript (builder-ui):**

```
You are reviewing a React/TypeScript PR for code quality. Return ONLY a JSON array of issues. No preamble.

Project rules:
- React 18, Apollo Client 3.x, Tailwind CSS, Lingui for i18n
- Components must be focused; extract hooks for reusable logic
- No business logic in UI — consume GraphQL only
- All user-facing strings MUST use Lingui translation macros
- Prettier: semi: false, singleQuote: true
- ESLint with react, react-hooks, jsx-a11y plugins enforced
- Comments only explain "why", never "what"
- Early returns over nested conditionals, destructuring for params

Check for:
- Unnecessary re-renders (missing memo, unstable refs in deps)
- Incorrect useEffect dependencies or stale closures
- State that should be derived, not stored
- Unnecessary complexity or over-abstraction
- `any` types where a proper type exists, or type assertions hiding errors

Diff (source files only):
{source_diff}
```

**For JavaScript services (identity, workflows-api):**

```
You are reviewing a Node.js/Express PR for code quality. Return ONLY a JSON array of issues. No preamble.

Project rules:
- Express 4.x, JavaScript ESM, Node 22
- Functions do one thing, early returns, destructuring
- All data queries MUST be tenant-scoped (mongoose-sublease)
- All new endpoints MUST have OpenTelemetry tracing spans
- Use @kualibuild/logger for structured logging with correlation IDs
- Use @kualibuild/errors for consistent error responses
- Comments only explain "why", never "what"
- identity service: lodash is strongly discouraged — use native Node 22 APIs
- Prettier: semi: false, singleQuote: true, trailingComma: none

Check for:
- Missing error handling on async operations
- Missing tenant scoping on database queries
- Missing tracing/metrics on new endpoints
- Callback hell or deeply nested promises
- Unnecessary complexity or over-abstraction
- Unsafe type coercion or missing null checks at boundaries
- New lodash usage in identity service (should use native alternatives)

Diff (source files only):
{source_diff}
```

#### Agent B: Security (model: sonnet)

Only launch this agent if the diff touches authentication, authorization, database queries, user input handling, or API endpoints. Skip for pure UI/styling/test-only changes.

```
You are a security reviewer for a multi-tenant SaaS platform. Return ONLY a JSON array of concrete, exploitable issues visible in the diff. No preamble, no theoretical risks.

Critical context — this is a multi-tenant app:
- Every data query MUST be tenant-scoped. Missing tenant scope = data leak across tenants.
- Auth via JWT (issued by identity service, validated by others via @kualibuild/authm-client)
- Service-to-service calls use @kualibuild/service2service with signed JWT
- User input arrives via GraphQL (platform) or REST (Node.js services)

Check for:
- Missing tenant scoping on queries (HIGHEST PRIORITY)
- Injection: SQL, NoSQL, command, XSS
- Auth/authz bypasses or missing permission checks
- Exposed secrets or credentials in code
- Insecure direct object references
- Unsafe deserialization or user input usage
- Missing CSRF protection on state-changing endpoints

{full_diff}
```

#### Agent C: Testing (model: haiku)

Only launch if the diff contains test files OR adds new public API surface (endpoints, mutations, exported functions) without corresponding tests.

```
You are a testing expert reviewing test quality. Return ONLY a JSON array of issues. No preamble.

Project testing standards by service:
- builder-ui: Vitest + @testing-library/react (coverage target: 40%→80%)
- identity: Mocha/Chai + Supertest, 100% coverage REQUIRED (non-negotiable)
- workflows-api: Jest + Supertest
- platform/tenant-manager: ExUnit + ExCoveralls

Check for:
- Tests that test implementation details instead of behavior
- Over-mocking that makes tests meaningless
- Missing integration tests for new endpoints/mutations
- Missing edge case coverage for critical paths
- Tests that don't assert anything meaningful
- New public API surface without corresponding tests
- Brittle tests coupled to internal structure

Diff (test files and any new public API surface):
{test_diff_and_new_api_surface}
```

### Step 5: Collect and Deduplicate Results

After all agents complete:

1. Parse each agent's JSON output
2. Deduplicate: if multiple agents flag the same file+line, merge into one comment
3. Sort: critical first, then suggestions; within each, sort by file path then line number

### Step 6: Display Results

```markdown
## Critical Issues (must fix before merge)

**{file}:{line}** — {comment}

## Suggestions (non-blocking improvements)

**{file}:{line}** — {comment}
```

If no issues in a category, say so briefly.

### Step 7: Ask for Approval

Ask: "Post these comments to the PR?"

Options:
- **Post all** — post everything
- **Post critical only** — only critical issues
- **Edit first** — let user modify
- **Cancel** — don't post

### Step 8: Post Comments

If approved, post as a single PR review with inline comments:

```bash
gh api repos/{owner}/{repo}/pulls/{number}/reviews \
  --method POST \
  -f event="COMMENT" \
  -f body="Review by automated PR review agents" \
  --jsonc "$(cat <<'EOF'
{
  "comments": [
    {
      "path": "{file}",
      "line": {line},
      "body": "{comment}"
    }
  ]
}
EOF
)"
```

If inline comments fail (line not in diff hunk), fall back to a single review body:

```markdown
## Automated PR Review

### Critical Issues
- **{file}:{line}** — {comment}

### Suggestions
- **{file}:{line}** — {comment}
```

## Cost Model

| Agent | Model | When | Rationale |
|-------|-------|------|-----------|
| Code Quality | haiku | Always | Single agent covers compliance + language + simplicity + a11y. Haiku handles pattern-based checks well with good context. |
| Security | sonnet | Conditional | Only for diffs touching auth/data/APIs. Security judgment needs stronger model. |
| Testing | haiku | Conditional | Only when tests exist or are missing for new API surface. |

**Typical cost**: 1-2 agents for most PRs (code quality + maybe testing), 2-3 for PRs touching auth/data paths. Down from 9 agents previously.

## Error Handling

- If `gh` CLI is not authenticated, tell the user to run `gh auth login`
- If the PR URL is invalid, ask for a corrected URL
- If an agent returns malformed JSON, skip it and note which agent failed
- If posting comments fails, display comments in terminal for manual posting
