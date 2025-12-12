---
model: haiku
---

# Prime

Load context about the codebase to prepare for upcoming tasks.

## Execution

### Step 1: Map Codebase Structure
Run `git ls-files | head -200` to understand file organization.

### Step 2: Read Core Documentation (in parallel)
- `README.md` - Project overview and conventions
- `CLAUDE.md` or `AGENTS.md` - AI development guidelines (if exists)
- `CLAUDE.local.md` - Personal AI development guidelines

## Output

Provide a brief summary of:
- Project purpose
- Key directories and their roles
- Ready state for next instruction
