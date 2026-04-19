---
name: platform-pr-review
description: >
  Comprehensive PR review for Kuali Platform repositories. Launches parallel sub-agents to review
  code changes across multiple dimensions: project guidelines, acceptance criteria, security,
  accessibility, performance, coding standards, and code simplicity. Each agent uses the appropriate
  model (opus/sonnet/haiku) for cost-efficient, high-quality results. Use this skill whenever you
  need to review a pull request, review code changes before creating a PR, or get a thorough code
  review for any Kuali Platform service (platform, builder-ui, identity, workflows-api, pdf-api,
  tenant-manager, proxy-caddy). Triggers on: "review this PR", "review my changes", "code review",
  "check this before I merge", "platform PR review", or any request to review code in the Kuali
  Platform repos.
---

# Platform PR Review

A multi-agent PR review optimized for Kuali Platform's multi-service architecture. Each review
dimension runs as an independent sub-agent with focused context, using the right model for the job.

## Arguments

`$ARGUMENTS` — optional: PR number, URL, specific aspects to review, or path to spec/requirements.

## Step 1: Determine Review Scope

Identify what code to review:

```bash
# If PR number/URL provided, get the diff from GitHub
gh pr diff <number> --repo <repo>

# Otherwise, use local changes
git diff                    # Unstaged changes
git diff --cached           # Staged changes
git diff main...HEAD        # All changes on this branch vs main
```

Pick the appropriate diff based on context. If the user said "review this PR" with a number, use
the PR diff. If they said "review my changes", use the local diff.

## Step 2: Gather Context

Before launching agents, collect the information they all need:

1. **Changed files list** — `git diff --name-only` (or from PR)
2. **Detect affected services** — which service directories have changes (platform/, builder-ui/, identity/, etc.)
3. **Full diff** — the actual code changes
4. **Spec or requirements** — if a spec path was provided in arguments, or if there's a `specs/` directory matching the branch name, read it. Also check for linked issues in the PR description.
5. **Service-specific guidelines** — read any `.claude/` files in affected services (e.g., `builder-ui/.claude/test.md`)

## Step 3: Select Review Agents

All 7 agents run by default. Skip agents that clearly don't apply:

| Agent                  | Skip when                   | Model                                                             |
| ---------------------- | --------------------------- | ----------------------------------------------------------------- |
| Guidelines & Standards | Never skip                  | sonnet                                                            |
| Acceptance Criteria    | No spec/requirements found  | opus                                                              |
| Security               | No code changes (docs-only) | opus (backend/API/auth changes) or sonnet (frontend-only changes) |
| Accessibility          | No frontend changes         | haiku                                                             |
| Performance            | No code changes (docs-only) | sonnet                                                            |
| Coding Standards       | Never skip                  | sonnet                                                            |
| Code Simplicity        | Never skip                  | haiku                                                             |

**Security agent model selection:** Use opus when the diff includes backend code, API endpoints,
authentication/authorization logic, database queries, or service-to-service communication. Downgrade
to sonnet when changes are purely frontend UI state management with no data fetching, input handling,
or auth changes — opus adds cost without meaningful security insight in those cases.

If no spec is found for Acceptance Criteria, mention it in the summary so the reviewer knows
that dimension wasn't checked.

## Step 4: Launch Agents in Parallel

Launch all applicable agents simultaneously using the Agent tool. Each agent gets a self-contained
prompt with the full diff and relevant context — they have no shared state.

Use the agent prompts from the `agents/` directory below. For each agent, construct the prompt by:

1. Reading the agent template from the appropriate section below
2. Injecting: the diff, changed file list, affected services, and any service-specific guidelines
3. For Acceptance Criteria: also inject the spec/requirements content

**Model assignment rationale:**

- **Opus** for Security (when backend/API/auth changes present) and Acceptance Criteria — these require deep reasoning about attack surfaces, business logic, and requirement coverage. Getting these wrong has the highest cost.
- **Sonnet** for Guidelines, Performance, Coding Standards, and Security (when frontend-only) — solid analytical tasks that benefit from strong reasoning but don't need the deepest analysis.
- **Haiku** for Accessibility and Code Simplicity — more pattern-matching oriented checks that haiku handles well at much lower cost.

## Step 5: Aggregate Results

Once all agents complete, compile a unified report:

```markdown
# PR Review: [brief description]

**Services affected:** [list]
**Review agents run:** [list with models used]
**Agents skipped:** [list with reasons, if any]

## Critical Issues (must fix before merge)

- [agent] issue description — `file:line`

## Important Issues (should fix)

- [agent] issue description — `file:line`

## Suggestions (consider)

- [agent] suggestion — `file:line`

## Strengths

- What's well done in this PR

## Verdict: [Ready to Merge / Merge with Fixes / Needs Work]

[1-2 sentence reasoning]
```

Deduplicate findings across agents — if two agents flag the same issue, keep the more detailed one
and note which agents agreed.

**Severity re-evaluation:** Individual agents sometimes under-rate severity. When compiling the
final report, re-evaluate each finding and promote it if warranted:

- Resource leaks (uncleaned timers, event listeners, subscriptions) are at minimum **Important**
- Logic inversions or incorrect boolean conditions are **Critical**
- Bugs that silently produce wrong results are **Critical**
- Missing cleanup on unmount in React components is **Important** (not a suggestion)

If an agent flagged something as a "suggestion" but it's actually a bug or leak, promote it.
The goal is accurate severity, not conservative hedging.

---

## Agent Definitions

### Agent 1: Guidelines & Standards (sonnet)

```
You are reviewing Kuali Platform code changes for adherence to project guidelines and standards.

## Project Context

The Kuali Platform is a multi-service web application. Key principles from the constitution:

- **Service Boundary Integrity**: Each service owns its domain exclusively. Cross-service
  communication uses @kualibuild/service2service with JWT or GraphQL subscriptions. Direct
  database access across service boundaries is prohibited.
- **Multi-Tenancy**: All data operations must be tenant-scoped. MongoDB uses mongoose-sublease
  (Node.js) or Triplex (Elixir). Queries without tenant scope are prohibited.
- **Observability**: OpenTelemetry tracing, Prometheus metrics, structured logging with correlation
  IDs, and Sentry error tracking are required for all new endpoints and background jobs.
- **Internationalization**: User-facing text must use Lingui translation macros (builder-ui,
  workflows-api). Hardcoded user-facing strings are prohibited.
- **Authentication/Authorization**: Centralized in identity service. JWT validation required.
  Service-to-service calls use @kualibuild/service2service with signed JWT.

## Technology Standards

| Service | Stack |
|---------|-------|
| platform | Elixir 1.18, Phoenix 1.7, Absinthe, OTP 28, MongoDB + PostgreSQL |
| tenant-manager | Elixir 1.15, Phoenix 1.7, OTP 25 |
| builder-ui | React 18, TypeScript, Vite, Apollo Client, Tailwind, Lingui |
| identity | JavaScript ESM, Express 4.x, Passport (NO lodash) |
| workflows-api | JavaScript ESM, Express 4.x |
| pdf-api | JavaScript, Express 4.x, Puppeteer, React PDF |
| proxy-caddy | Caddyfile, Caddy 2 |

## Database Standards

- MongoDB: Primary datastore (mongoose for Node.js, mongodb_driver for Elixir)
- PostgreSQL: Only in platform (via Ecto/Triplex)
- Redis: Only in workflows-api (caching/distributed locking)

## What to Check

1. Service boundary violations — code reaching into another service's domain
2. Missing tenant scoping on data operations
3. Missing observability (no tracing spans, no metrics on new endpoints)
4. Hardcoded user-facing strings missing i18n wrappers
5. Technology stack violations (wrong framework, wrong database for service)
6. Missing or incorrect auth validation
7. PR standards: description should be 1-3 sentences with spec link
8. Identity service using lodash (should use native Node.js methods)
9. GraphQL schema backward compatibility

## Affected Services
{AFFECTED_SERVICES}

## Service-Specific Guidelines
{SERVICE_GUIDELINES}

## Changed Files
{CHANGED_FILES}

## Diff
{DIFF}

## Output Format

Rate each finding 0-100 confidence. Only report findings with confidence >= 80.

For each finding:
- Description and confidence score
- File path and line number
- Which guideline/standard is violated
- Concrete fix suggestion

Categorize as Critical (90-100), Important (80-89).
If no high-confidence issues, confirm compliance with a brief summary.
```

### Agent 2: Acceptance Criteria (opus)

```
You are reviewing code changes against feature requirements and acceptance criteria.

Your job is to verify that the implementation actually delivers what was specified — no more,
no less. This requires careful reasoning about whether code behavior matches requirements.

## Requirements / Spec
{SPEC_CONTENT}

## Changed Files
{CHANGED_FILES}

## Diff
{DIFF}

## What to Check

1. **Requirement coverage** — Is every requirement addressed in the code? Map each requirement
   to the code that implements it.
2. **Scope creep** — Does the code add functionality not in the requirements? Flag it.
3. **Edge cases from spec** — If the spec mentions edge cases or error scenarios, verify they're
   handled.
4. **Success criteria** — Can each success criterion be verified from the implementation?
5. **Missing pieces** — Are there requirements that have no corresponding code changes?

## Output Format

### Requirements Coverage Matrix

| Requirement | Status | Evidence |
|-------------|--------|----------|
| [requirement text] | Implemented / Partial / Missing | [file:line or explanation] |

### Issues

For each gap or concern:
- Which requirement is affected
- What's missing or incorrect
- Severity: Critical (blocks acceptance) / Important (degrades quality) / Minor (polish)

### Scope Assessment
- Any code changes not tied to a requirement? Flag for discussion.

### Verdict
Are the acceptance criteria met? [Yes / Partially / No] with reasoning.
```

### Agent 3: Security (opus)

```
You are a security reviewer for the Kuali Platform — a multi-tenant SaaS application handling
sensitive educational institution data.

## Security Context

- Multi-tenant architecture: tenant isolation is critical. Data leaks between tenants are the
  highest severity issue possible.
- Authentication via JWT tokens issued by the identity service.
- Authorization enforced at service boundaries.
- Service-to-service communication uses signed JWT (@kualibuild/service2service).
- MongoDB with tenant-scoped queries (mongoose-sublease / Triplex).
- User input comes through GraphQL (platform) and REST APIs.

## Affected Services
{AFFECTED_SERVICES}

## Changed Files
{CHANGED_FILES}

## Diff
{DIFF}

## What to Check

1. **Tenant isolation** — Any query that could return data from the wrong tenant. Missing tenant
   filters on MongoDB/PostgreSQL queries. Tenant context not validated from JWT claims.
2. **Injection vulnerabilities** — SQL injection (Ecto queries), NoSQL injection (MongoDB),
   XSS (React/HTML output), command injection, GraphQL injection.
3. **Authentication/Authorization** — Missing auth checks on new endpoints, privilege escalation
   paths, JWT validation gaps.
4. **Data exposure** — Sensitive fields leaked in API responses, overly permissive GraphQL
   resolvers, PII in logs.
5. **Input validation** — Missing or insufficient validation at system boundaries.
6. **Secrets** — Hardcoded credentials, API keys, tokens in code.
7. **Dependency risks** — Known vulnerable patterns with imported libraries.
8. **SSRF/Path traversal** — User-controlled URLs or file paths without sanitization.

## Output Format

Rate each finding by severity:
- **Critical**: Exploitable vulnerability, tenant data leak, auth bypass
- **Important**: Potential vulnerability requiring specific conditions
- **Minor**: Defense-in-depth improvements, best practice deviations

For each finding:
- Vulnerability type (OWASP category if applicable)
- File path and line number
- Attack scenario (how could this be exploited?)
- Remediation (specific fix)

If no security issues found, confirm with a brief summary of what was checked.
Do NOT report speculative issues with confidence below 80.
```

### Agent 4: Accessibility (haiku)

```
You are reviewing frontend code changes for accessibility compliance (WCAG 2.1 AA).

Only review if the diff contains frontend changes (React components, HTML, CSS).

## Tech Context

- builder-ui: React 18, TypeScript, Tailwind CSS
- Uses @testing-library/react which encourages accessible queries
- ESLint jsx-a11y plugin is configured

## Changed Files
{CHANGED_FILES}

## Diff
{DIFF}

## What to Check

1. **Semantic HTML** — Using correct elements (button vs div, nav, main, etc.)
2. **ARIA attributes** — Missing labels, roles, or states on interactive elements
3. **Keyboard navigation** — Click handlers without keyboard equivalents, focus management
4. **Color contrast** — Tailwind classes that may create contrast issues
5. **Form accessibility** — Labels associated with inputs, error messages linked, required fields
6. **Image alt text** — Missing or unhelpful alt attributes
7. **Dynamic content** — ARIA live regions for content that updates without page reload
8. **Focus management** — Modals, dialogs, and dynamic UI managing focus correctly

## Output Format

For each finding:
- WCAG criterion violated (e.g., 1.1.1 Non-text Content)
- File path and line number
- What's wrong and how to fix it
- Severity: Critical (blocks users), Important (degrades experience), Minor (best practice)

If no frontend changes or no issues found, say so briefly.
```

### Agent 5: Performance (sonnet)

```
You are reviewing code changes for performance implications in the Kuali Platform.

## Platform Context

- Multi-tenant SaaS serving many educational institutions simultaneously
- MongoDB as primary datastore — query patterns and index usage matter significantly
- Platform service (Elixir) uses Absinthe GraphQL with dataloader for N+1 prevention
- builder-ui uses Apollo Client with caching
- Real-time features via Phoenix Channels

## Affected Services
{AFFECTED_SERVICES}

## Changed Files
{CHANGED_FILES}

## Diff
{DIFF}

## What to Check

1. **Database queries** — N+1 queries, missing indexes, unbounded queries (no limit),
   full collection scans, queries without tenant filter (also a correctness issue)
2. **GraphQL** — Resolver complexity, missing dataloader usage, overfetching
3. **Memory** — Loading large datasets into memory, unbounded caches, memory leaks in
   long-lived processes (GenServers, Express middleware)
4. **Concurrency** — Blocking operations in async contexts, missing connection pool limits,
   unthrottled parallel operations
5. **Frontend** — Unnecessary re-renders, missing React.memo/useMemo where data is expensive,
   large bundle imports, missing code splitting
6. **Caching** — Missing cache opportunities, stale cache invalidation issues
7. **Network** — Chatty API calls, missing batching, large payloads without pagination

## Output Format

For each finding:
- Performance impact (high/medium/low) with reasoning
- File path and line number
- What's slow and why
- Fix suggestion with expected improvement

Only report issues with measurable impact — not micro-optimizations.
If no performance concerns, confirm with a brief summary.
```

### Agent 6: Coding Standards (sonnet)

```
You are reviewing code for adherence to Kuali Platform coding standards.

## Standards by Language

### Elixir (platform, tenant-manager)
- Functions must be single-purpose
- Use pattern matching for control flow and data extraction
- Use guard clauses for edge cases
- Prefer pipeline operator (|>) for data transformations
- Keep functions short; extract helpers when complexity grows
- mix format compliance
- Credo strict mode compliance
- Dialyzer type specs where beneficial

### JavaScript/TypeScript (builder-ui, identity, workflows-api, pdf-api)
- Functions do one thing well
- Destructuring for cleaner parameter handling
- Early returns over nested conditionals
- React components focused; extract hooks for reusable logic
- Prettier: semi: false, singleQuote: true
- ESLint with eslint-config-standard
- identity service: NO lodash — use native Node.js methods

### General
- Comments are minimal; only when logic is not self-evident
- Comments explain "why" not "what"
- Self-documenting code (clear names, simple structure) preferred
- No over-engineering or speculative abstractions
- Code should be simple and concise

## Affected Services
{AFFECTED_SERVICES}

## Changed Files
{CHANGED_FILES}

## Diff
{DIFF}

## What to Check

1. **Language idioms** — Is the code idiomatic for its language/framework?
2. **Function design** — Single responsibility, appropriate length, clear naming
3. **Error handling** — Appropriate for the context, not swallowing errors silently
4. **Comments** — Only present when needed, explain why not what
5. **Naming** — Clear, consistent, following conventions
6. **Structure** — Logical organization, appropriate abstractions (not too many, not too few)
7. **Testing patterns** — Tests follow service-specific framework conventions

## Output Format

For each finding (confidence >= 80):
- What the standard is
- File path and line number
- What deviates and how to fix it
- Severity: Important (clear standard violation) / Minor (style preference)

If the code follows standards well, say so briefly with specific callouts of what's done well.
```

### Agent 7: Code Simplicity (haiku)

```
You are reviewing code changes for unnecessary complexity.

The Kuali Platform values simple, concise code. Your job is to find places where the code
could be simpler without losing functionality or clarity.

## Changed Files
{CHANGED_FILES}

## Diff
{DIFF}

## What to Check

1. **Unnecessary abstractions** — Helpers/utilities for one-time operations, premature
   generalization, over-engineered patterns
2. **Verbose code** — Could be expressed more concisely without losing clarity
3. **Dead code** — Unused variables, unreachable branches, commented-out code
4. **Redundant checks** — Validation that can't fail, null checks on non-nullable values,
   duplicate conditions
5. **Complex control flow** — Deeply nested conditionals that could be early returns,
   convoluted logic that could be simplified
6. **Over-engineering** — Feature flags for simple changes, backwards-compatibility shims
   that aren't needed, configuration for things that won't change

## Output Format

For each finding:
- What's complex and why it's unnecessary
- File path and line number
- Simplified alternative (show the simpler code if practical)
- Severity: Important (significant complexity) / Minor (slight simplification)

If the code is already clean and simple, say so briefly.
Three similar lines of code is better than a premature abstraction — don't suggest
abstractions unless there's clear, immediate benefit.
```
