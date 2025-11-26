# PR Review Comments

Review all comments on the pull request for the current branch and create actionable plans to address them.

## Instructions

1. **Fetch PR comments**: Run `gh pr view --json comments,reviews` to get all comments and review comments on the current branch’s PR.
1. **Categorize the feedback**: Group comments by type:

- Code issues (bugs, logic errors)
- Style/formatting concerns
- Architecture/design feedback
- Documentation requests
- Questions needing clarification

1. **Create implementation plan**: Use the `/plan-chore` command to draft a plan that addresses each comment. Include:

- Specific file and line references
- The requested change or fix
- Any dependencies between changes

1. **Propose Claude.local.md entry**: Analyze patterns in the feedback to identify recurring issues or team preferences. Draft a new section for `Claude.local.md` that will help avoid similar issues in future work. Format as:

```markdown
## [Category Name]

- [Specific guideline derived from PR feedback]
- [Another guideline]
```

## Output

Provide:

1. A summary of all PR comments found
1. The full plan-chore output addressing each item
1. The proposed Claude.local.md addition with rationale
