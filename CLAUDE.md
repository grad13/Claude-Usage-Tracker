# WeatherCC

macOS menu bar app for Claude Code usage monitoring.

## Process (STRICT ORDER — skipping steps is forbidden)

1. **Read docs** — Read must-read files before any work
2. **Understand approach** — State the approach in your own words. Don't list actions. Explain WHY
3. **Write plan** — Write the plan in `ClaudeLimits/docs/plans/`. Not in chat. In the file
4. **Get approval** — User approves the plan before any code changes
5. **Execute** — Implement according to the approved plan
6. **Document results** — Update docs with what was done, what changed, what's unverified

**Violating this order is the single most common failure.** Every major mistake in this project came from skipping step 2 or 3.

## Requirements (non-negotiable)

0. **Do not ignore what has been said** — Read all docs before working. Do not repeat past mistakes. Use information already gathered (externals/, reference/). Never say "unknown" about things already investigated
1. **Write original code** — AgentLimits is reference only. Never copy code
2. **Document everything** — Update docs BEFORE changing code
3. **Write tests** — State what tests cover and don't cover
4. **App must work (deprioritizable)** — If 0-3 are met, this can be compromised

## Session Start — Must-Read Files

- `ClaudeLimits/docs/CLAUDE.md` — entry point with full document map
- `ClaudeLimits/docs/plans/overview.md` — roadmap, current phase, next work
- `ClaudeLimits/docs/spec/architecture.md` — design decisions
- `ClaudeLimits/docs/decisions/usage-data-approaches.md` — A/B/C/D decision (CRITICAL)
- `ClaudeLimits/docs/reference/working-principles.md` — development rules

## Common Failures (DO NOT REPEAT)

- **Building on unverified foundations** — Verify data retrieval works BEFORE building UI on top of it
- **Saying "unknown" about investigated things** — externals/claude-site/ has the API response structure. reference/api-response.md documents it. USE THEM
- **Asking questions instead of thinking** — When you have the information, make the decision yourself
- **Listing actions instead of explaining approach** — "What" without "why" means you don't understand
- **Skipping plan mode** — No code changes without a written, approved plan in docs/plans/

## Build

```bash
xcodebuild -scheme WeatherCC -destination 'platform=macOS' build
```

## Structure

- Source: `ClaudeLimits/src/WeatherCC/`
- Tests: `ClaudeLimits/tests/WeatherCCTests/`
- Docs: `ClaudeLimits/docs/` (not git-tracked)
- Reference: `ClaudeLimits/externals/` (not git-tracked)
- Scripts: `ClaudeLimits/scripts/`

## Rules

- Communicate in Japanese
- No throwaway scripts — write reusable scripts in `scripts/`
- Never claim "done" without evidence
- Report status as: confirmed (tested on device with date) / unit-tested (test name) / unverified
- When asked for proposals, give concrete proposals (don't answer with questions)
