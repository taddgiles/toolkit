# Elixir Best Practices Plugin

A comprehensive Claude Code plugin that enforces Elixir and OTP best practices through specialized agents for code review, architecture design, and test-driven development.

## Overview

This plugin provides four specialized agents that help you write idiomatic, maintainable Elixir code:

1. **elixir-code-reviewer** - Reviews Elixir code for best practices compliance
2. **otp-reviewer** - Reviews OTP implementations (GenServers, Supervisors, Tasks)
3. **elixir-architect** - Designs Elixir features following functional programming principles
4. **elixir-tdd** - Guides test-driven development with ExUnit

## Installation

The plugin is already installed in your project at `.claude/plugins/elixir-best-practices`.

To use it in other projects, copy the entire plugin directory to:
- Project-specific: `<project>/.claude/plugins/elixir-best-practices`
- Global: `~/.claude/plugins/elixir-best-practices`

## Usage

### Using Agents with the Task Tool

Invoke agents using the Task tool in Claude Code:

```
Use the Task tool with subagent_type="elixir-best-practices:elixir-code-reviewer" to review my recent Elixir changes
```

### Agent Reference

#### 1. Elixir Code Reviewer

**When to use:** After writing or modifying Elixir code

**What it does:**
- Reviews pattern matching usage
- Checks error handling patterns
- Identifies common anti-patterns (nested case, String.to_atom on user input, etc.)
- Validates function design (naming, guard clauses, multiple clauses)
- Reviews data structure choices

**Example invocation:**
```
Please use the Task tool with subagent_type="elixir-best-practices:elixir-code-reviewer"
to review the files I just modified
```

**Agent reviews:**
- Pattern matching vs conditionals
- Error tuple usage (`{:ok, _}` | `{:error, _}`)
- Enum vs Stream for large collections
- Function naming and design
- Data structure appropriateness

---

#### 2. OTP Reviewer

**When to use:** After writing or modifying GenServers, Supervisors, or Task code

**What it does:**
- Reviews GenServer implementations
- Validates process communication patterns (call vs cast)
- Checks fault tolerance design
- Reviews Task and async operation handling
- Evaluates supervisor configuration

**Example invocation:**
```
Use the Task tool with subagent_type="elixir-best-practices:otp-reviewer"
to review my GenServer implementation
```

**Agent reviews:**
- GenServer state management
- `call` vs `cast` usage
- Timeout configurations
- Task supervision and error handling
- Supervisor restart policies

---

#### 3. Elixir Architect

**When to use:** Before implementing new features or modules

**What it does:**
- Designs idiomatic Elixir solutions
- Plans data structures (structs, maps, keyword lists)
- Creates function signature designs with proper error handling
- Provides implementation blueprints
- Suggests pattern matching strategies

**Example invocation:**
```
Use the Task tool with subagent_type="elixir-best-practices:elixir-architect"
to design a user authentication module
```

**Agent provides:**
- Module structure and organization
- Data structure definitions
- Public API design
- Error handling patterns
- Implementation guidance

---

#### 4. Elixir TDD

**When to use:** Implementing features with test-driven development

**What it does:**
- Guides Red-Green-Refactor cycle
- Writes comprehensive ExUnit tests
- Ensures implementations follow best practices
- Applies property-based testing where appropriate
- Maintains test organization

**Example invocation:**
```
Use the Task tool with subagent_type="elixir-best-practices:elixir-tdd"
to implement a price calculation feature using TDD
```

**Agent guides:**
- Test case planning
- Writing failing tests first
- Implementing minimum code following best practices
- Refactoring with tests as safety net
- Comprehensive coverage

## Best Practices Enforced

### Elixir Core
- **Pattern matching** over conditionals
- **Error tuples** (`{:ok, result}` | `{:error, reason}`)
- **Guard clauses** for validation
- **Multiple function clauses** over complex conditionals
- **Descriptive naming** (predicates end in `?`)
- **Stream** for large collections
- **Standard library** functions over manual recursion
- Avoid: `String.to_atom/1` on user input, nested case, process dictionary

### OTP
- **GenServer**: Simple state, `handle_continue/2` for post-init, `terminate/2` cleanup
- **Communication**: `call` for sync, `cast` for fire-and-forget, prefer `call` for back-pressure
- **Fault Tolerance**: Design for restart, proper supervisor config
- **Tasks**: Use `Task.Supervisor`, handle failures, set timeouts, use `async_stream`

### Testing
- **TDD workflow**: Red → Green → Refactor
- **Test organization**: One module per source file, clear descriptions
- **Coverage**: Happy path, error conditions, edge cases
- **ExUnit features**: Tags, setup, proper assertions
- **Property testing**: Use StreamData for invariants

## Workflow Examples

### Example 1: Review Existing Code

```
I just finished implementing a user registration feature.
Use the Task tool with:
- subagent_type="elixir-best-practices:elixir-code-reviewer" for general Elixir review
- subagent_type="elixir-best-practices:otp-reviewer" for the GenServer components
```

### Example 2: Design New Feature

```
I need to implement a caching system.
Use the Task tool with subagent_type="elixir-best-practices:elixir-architect"
to design the architecture before I start coding.
```

### Example 3: TDD Implementation

```
Use the Task tool with subagent_type="elixir-best-practices:elixir-tdd"
to help me implement a JSON parser using test-driven development.
```

### Example 4: Full Development Cycle

```
1. Design: Use elixir-architect to plan the feature
2. Implement: Use elixir-tdd to build with tests
3. Review: Use elixir-code-reviewer and otp-reviewer to validate
```

## Source Rules

This plugin enforces rules from:
- `usage_rules_elixir.md` - Core Elixir patterns and practices
- `usage_rules_otp.md` - OTP design patterns

## Tips

1. **Use agents proactively** - Don't wait for problems, review as you code
2. **Combine agents** - Use architect before coding, TDD during, reviewers after
3. **Incremental reviews** - Review small changes frequently rather than large batches
4. **Learn patterns** - Agent feedback teaches idiomatic Elixir over time

## Support

For issues or suggestions:
1. Check the agent prompt files in `.claude/plugins/elixir-best-practices/agents/`
2. Modify agents to fit your team's specific practices
3. Contribute improvements back to your team

## License

Project-specific plugin - customize as needed for your organization.
