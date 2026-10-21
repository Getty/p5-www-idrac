# WWW-iDRAC House Rules

Apply to every task in this repository unless explicitly overridden. Bias: caution over
speed on non-trivial work; use judgment on trivial tasks. Loaded automatically at launch (same
priority as `CLAUDE.md`). Subagents get their discipline via skills force-loaded by `briefing.skills`.

## Engineering discipline

1. **Think before coding** — state assumptions. When uncertain, ask rather than guess.
2. **Simplicity first** — minimum code that solves the problem; nothing speculative.
3. **Surgical changes** — touch only what you must; match existing style.
4. **Tests verify intent, not just behavior** — reproduce a bug before fixing it; leave a
   regression test behind. A test that can't fail when the logic changes is wrong.
5. **Read before you write** — before new code, read the callers and the sibling module (`WWW::iDRAC::Redfish` ↔ the capability classes).
6. **Surface conflicts, don't average them** — pick one pattern, explain why, flag the other for cleanup.
7. **Checkpoint after every significant step** — done / verified / left.
8. **Fail loud** — "done" is wrong if anything was skipped silently.

## Delegation

This rule depends on whether the Agent/Task tool is available to you.

- **You can spawn subagents** (orchestrating main agent): do NOT touch behavior-relevant code yourself —
  delegate to this repo's worker. Your lane: coordinate, inspect, plan, review diffs, run tests, edit
  non-behavioral docs. When in doubt, delegate. Why: only the `www-idrac-*` agents are briefed.

  | Task | Agent |
  |---|---|
  | Implement / refactor / debug behavior-relevant code | `www-idrac-worker` (default) |
  | Write/extend tests | `www-idrac-test-writer` |
  | Commits, `Changes`, card → done, pre-release audit | `www-idrac-release-manager` |
  | Write/maintain POD | `www-idrac-doc-writer` |

- **You cannot spawn subagents** (you ARE a `www-idrac-*` agent): the delegation lock does not apply to you — implement, refactor, debug, and test per these rules.

Behavior-relevant = runtime behavior, the public API (`WWW::iDRAC`, `::Redfish`, `::System`, `::Power`, `::Sensors`,
`::Logs`, `::Manager`, `::Capabilities`, `::Racadm`, `::Racadm::SSH`, `::Bios`, `::Jobs`, `::VirtualMedia`),
the fixed return keys, error handling, tests, performance. Pure prose docs and `Changes` notes are not.

**Only `www-idrac-release-manager` commits.** A worker leaves a commit-ready tree and hands its
card to `review`; you then dispatch `www-idrac-release-manager` to cut the commit and close it.

## Hazards — the short form (mechanism and background: skill `www-idrac-core`)

- **Live tests hit a real management controller.** Opt-in via `IDRAC_HOST`/`IDRAC_USERNAME`/`IDRAC_PASSWORD`,
  read-only. Never run them uncontrolled or in a fanned-out context; a default `prove -lr t` must pass with them skipped.
- **Never set `IDRAC_LIVE_DESTRUCTIVE=1`** — it switches the machine off and restarts its controller. Only the maintainer runs that part.
- **An iDRAC allows only a few sessions.** Code that logs in must end its session; a test that leaves one open is a defect.
- **Translation stays apart from I/O** — keep the `*_from` functions and `Role::HTTP`'s `build_request`/`read_response` free of I/O.
- **Nothing about the controller comes from memory** — iDRAC facts come from a recorded
  controller or Dell's documentation; the real answers live in `t/fixtures/`.
- **Always `prove -lr t`, never plain `prove -l t/`** — the plain runner is non-recursive and skips the subdir tests silently.

## Coordination — karr board (always in scope)

`karr` is the internal board — git-native, state in `refs/karr/*`, one board per repo. Ticket
coordination is the orchestrating agent's job: just use it, don't invoke a skill first. Surface: skill
`kanban-issues-karr-coordination`.

- `karr list --compact` / `karr board` — open work · `karr show ID` — detail
- `karr create "Title" --priority high --tags a,b --body '…'` — new ticket
- `karr move ID in-progress --claim NAME` — start · `karr handoff ID --claim NAME --note "…"` — to review
- mutating commands auto-sync; `karr sync --pull|--push` for explicit exchange

**Serialize board mutations when fanning out.** Keep implementation work parallel, but collect results
and then loop `karr move`/`handoff`/`sync` sequentially — concurrent board writes are a resource event
(this shared box has OOM-rebooted on it). No background poll loops: check once, act.

**Fixtures are public.** Nothing recorded from a real controller is committed before it went
through `iDRACSanitize` and a person has read it.

## Release — never without permission

`prove -lr t` and `dzil build`/`dzil test` are fine anytime. `dzil release`, any CPAN upload, `git push` and
any tag are STRICTLY forbidden without the maintainer's explicit go-ahead — even if a plan lists "release"
as the next step. Heading toward release: stop and ask.

## Public issues — never act without instruction

Two trackers, two universes. **karr** is the internal agent work board, churned freely. A public tracker
(GitHub) carries real humans' issues, written under the maintainer's account. Never act on a public issue on
your own initiative — not even to read it. No listing, viewing, commenting, editing, closing or creating
unless the user explicitly says to handle a specific issue.

## Perl specifics — reference, don't restate

Module loading, Moo patterns, dependency pinning, `[@Author::GETTY]` release metadata, POD directives and house
style live in skills `getty-perl-core`, `getty-perl-moo`, `perl-release-dist-ini`, `getty-perl-release-author-getty`
and `www-idrac-core` (force-loaded for `www-idrac-*` agents). Do not duplicate that content here.
