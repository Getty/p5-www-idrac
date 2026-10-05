# CLAUDE.md

WWW::iDRAC — synchronous Perl client for Dell iDRAC: inventory, power, sensors, logs and
the controller itself, behind a facade cut by capability, not by protocol. Phase 1 fetches
everything over Redfish. Moo-based; released to CPAN via Dist::Zilla `[@Author::GETTY]`.

**Phase 1 is built, and has not met a real iDRAC yet.** Everything the code assumes about
the field names of an iDRAC 7 (PowerEdge R720xd) or iDRAC 8 (PowerEdge T330) is an
assumption until they are recorded: plan task 5 (recording both), step 3 of task 12 (every
reading method against the recordings) and step 3 of task 13 (the live run) are open, and
wait for the addresses and credentials in `~/.config/idrac/`. The design is
`docs/superpowers/specs/2026-10-04-www-idrac-design.md`, the plan
`docs/superpowers/plans/2026-10-04-www-idrac-phase-1.md`. Phase 2 (a second transport for
what Redfish lacks on iDRAC 7/8), the async twin `Net::Async::iDRAC` and phase 3
(iDRAC 9/10) are on the karr board.

## Modules

- `WWW::iDRAC` — facade: `host`, credentials, TLS options, one `LWP::UserAgent`; lazy
  `redfish`, `capabilities`, `system`, `power`, `sensors`, `logs`, `manager`.
- `WWW::iDRAC::Redfish` — the transport and the documented way out: session login, one
  re-login on 401, `get`/`post`/`patch`/`delete`, `members`, `locate`. Ends its session
  when destroyed. Translates nothing.
- `WWW::iDRAC::System`, `::Power`, `::Sensors`, `::Logs`, `::Manager` — the capability
  classes. Return hashes with fixed keys, never Redfish documents; each has `*_from`
  functions without I/O and a `probe_*` per public method.
- `WWW::iDRAC::Capabilities` — the facts, and `supports('area.method')`.
- `WWW::iDRAC::Role::Capability` — `resource`, `linked_path`, `fetch`, `unsupported`,
  `supports`. `WWW::iDRAC::Role::HTTP` — `build_request` / `read_response` / `send_request`.
- `WWW::iDRAC::Util` — `text`, `number`, `health_of`, `state_of`, `list_of`.
- `WWW::iDRAC::Error` — base; `::Validation`, `::Network`, `::API`, `::Unsupported`.

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
dzil test --all      # including the author and release tests
dzil build           # build the distribution

# the live suite, read-only, against a real iDRAC
IDRAC_HOST=... IDRAC_USERNAME=... IDRAC_PASSWORD=... IDRAC_SSL_FINGERPRINT='sha256$...' prove -lv t/90-live-idrac.t

# record a controller into t/fixtures/<name>/redfish.json (GET only, cleaned)
IDRAC_HOST=... IDRAC_USERNAME=... IDRAC_PASSWORD=... IDRAC_SSL_FINGERPRINT='sha256$...' perl -Ilib -It/lib t/idrac/record.pl <name>
```

`IDRAC_LIVE_DESTRUCTIVE=1` makes the live suite empty the event log, switch the server
off and on and restart the controller; `IDRAC_LIVE_FORCE_OFF=1` lets it cut the power
where the controller offers no gentle shutdown. Never set either yourself; they hit a
real machine.

A recording is only committed after a person has read it, and with an `expect.json`
beside it that says what the controller lacks; `t/85-fixtures.t` prints a first version.

`LICENSE` is committed, not generated at build time; re-run `dzil genlicense` and
`git add LICENSE` after changing license, holder or year in `dist.ini`.
