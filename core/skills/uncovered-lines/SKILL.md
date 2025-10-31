# Coverage Uncovered Lines

Lists uncovered line numbers per file from Elixir coverage reports.

## When to use
- When asked to show which lines are not covered.
- When asked to restrict to certain files (pass `--filter`).
- When asked to fail CI if coverage drops below a threshold.

## How to run
1) Generate a report:
- ExCoveralls JSON: `MIX_ENV=test mix coveralls.json` → `cover/excoveralls.json`
- LCOV: `MIX_ENV=test mix coveralls.lcov` → `cover/lcov.info`

2) Run the script:
- JSON: `node coverage-uncovered.js --json cover/excoveralls.json`
- LCOV: `node coverage-uncovered.js --lcov cover/lcov.info`
- Only files under `lib/my_app/`: add `--filter "lib\\/my_app\\/.*"`
- Enforce threshold: add `--fail-under 90`

## Output
Text (default) or JSON (`--format json`) with:
- Per-file: coverage %, covered/considered counts, and uncovered line numbers.
- Overall summary and optional non-zero exit if below `--fail-under`.
