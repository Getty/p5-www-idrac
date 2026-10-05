# CLAUDE.md

WWW::iDRAC — synchronous Perl client for Dell iDRAC: inventory, power, sensors, logs and
the controller itself, behind a facade cut by capability, not by protocol. Moo-based;
released to CPAN via Dist::Zilla `[@Author::GETTY]`.

Skeleton state: nothing is implemented yet. The design is
`docs/superpowers/specs/2026-10-04-www-idrac-design.md`, the plan
`docs/superpowers/plans/2026-10-04-www-idrac-phase-1.md`, the work is on the karr board.

## Delegation

Delegate behavior-relevant code to the right agent instead of touching it yourself —
principle and lane are in `.claude/rules/www-idrac-rules.md`.

| Task | Agent |
|---|---|
| Implement / refactor / debug behavior-relevant code | `www-idrac-worker` (default) |
| Write/extend tests | `www-idrac-test-writer` |
| Commits, `Changes`, card → done, pre-release audit | `www-idrac-release-manager` |
| Write/maintain POD | `www-idrac-doc-writer` |

The agents carry their skills via `briefing.skills` (see `.claude/agents/`); the main
agent delegates rather than loading them. Skill sources live under `.claude/skills/`.

## Commands

```bash
prove -lr t          # full test suite (recursive; the live test skips by default)
dzil build           # build the distribution
dzil test            # test via Dist::Zilla
```

`LICENSE` is committed, not generated at build time; re-run `dzil genlicense` and
`git add LICENSE` after changing license, holder or year in `dist.ini`.
