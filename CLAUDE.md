# CLAUDE.md

WWW::iDRAC — synchronous Perl client for Dell iDRAC: inventory, power, sensors, logs and
the controller itself over Redfish, and what Redfish lacks on iDRAC 7/8 (BIOS attributes,
job queue, virtual media, license) over racadm on SSH, behind a facade cut by capability,
not by protocol. Moo-based; released to CPAN via Dist::Zilla `[@Author::GETTY]`.

**Phase 1 is built.** Everything that reads has run against an iDRAC 7 (PowerEdge R720xd,
firmware 2.65) and an iDRAC 8 (PowerEdge T330, firmware 2.50), from recordings and live;
what they answered is in section 9 of the spec. **What switches has run against the
iDRAC 7 only**, on 2026-10-06 with the maintainer's leave: `clear_sel`, gentle `off`,
`on` and `manager->restart`. The forced forms and everything that switches on an
iDRAC 8 have not run against hardware. The design is
`docs/superpowers/specs/2026-10-04-www-idrac-design.md`, the plan
`docs/superpowers/plans/2026-10-04-www-idrac-phase-1.md`. The async twin
`Net::Async::iDRAC` and phase 3 (iDRAC 9/10) are on the karr board.

**Phase 2 is built** (2026-10-14): racadm over SSH as the second transport, chosen after
a read-only measurement of both controllers (section 9 of the spec). Everything that reads
has run against both, live and from recordings (`t/fixtures/idrac{7,8}/racadm.json`).
**Nothing that writes over racadm has run against hardware**: `bios->set`/`commit`,
`jobs->delete`, `virtual_media->connect`/`disconnect` are tested against `t/lib/FakeRacadm.pm`
only. These are never run by an agent; the live suite keeps them behind
`IDRAC_LIVE_DESTRUCTIVE=1`.

## Modules

- `WWW::iDRAC` — facade: `host`, credentials, TLS options, one `LWP::UserAgent`, the
  `ssh_*` options; lazy `redfish`, `racadm`, `capabilities`, `system`, `power`, `sensors`,
  `logs`, `manager`, `bios`, `jobs`, `virtual_media`.
- `WWW::iDRAC::Redfish` — the transport and the documented way out: session login, one
  re-login on 401, `get`/`post`/`patch`/`delete`, `members`, `locate`. Ends its session
  when destroyed. Translates nothing.
- `WWW::iDRAC::System`, `::Power`, `::Sensors`, `::Logs`, `::Manager` — the capability
  classes. Return hashes with fixed keys, never Redfish documents; each has `*_from`
  functions without I/O and a `probe_*` per public method.
- `WWW::iDRAC::Racadm` — the second transport: `run` sends one racadm command and returns
  the text; `quote`, `command_from`, `error_from`, `blocks_from` are pure. Closes its
  connection when destroyed. `WWW::iDRAC::Racadm::SSH` — the I/O, over Net::OpenSSH,
  replaceable through `runner`; host key checked, one login attempt.
- `WWW::iDRAC::Bios`, `::Jobs`, `::VirtualMedia` — the racadm capability classes, same
  rules as the Redfish ones (`*_from` without I/O, `probe_*` per method).
- `WWW::iDRAC::Capabilities` — the facts (license read lazily over racadm), and
  `supports('area.method')`.
- `WWW::iDRAC::Role::Transport` — `transport_name`, `logout`. `Role::Area` — `unsupported`,
  `supports`. `Role::Capability` — Area + `resource`, `linked_path`, `fetch` (Redfish).
  `Role::Racadm` — Area + `racadm_run` (license/SSH facts become Unsupported).
  `WWW::iDRAC::Role::HTTP` — `build_request` / `read_response` / `send_request`.
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

# the same for racadm over SSH (host key: IDRAC_SSH_HOST_KEY, IDRAC_SSH_KNOWN_HOSTS or IDRAC_SSH_VERIFY=0)
IDRAC_HOST=... IDRAC_USERNAME=... IDRAC_PASSWORD=... IDRAC_SSH_HOST_KEY='ssh-ed25519 AAAA...' prove -lv t/92-live-racadm.t

# record a controller into t/fixtures/<name>/redfish.json (GET only, cleaned)
IDRAC_HOST=... IDRAC_USERNAME=... IDRAC_PASSWORD=... IDRAC_SSL_FINGERPRINT='sha256$...' perl -Ilib -It/lib t/idrac/record.pl <name>

# and what racadm prints, into t/fixtures/<name>/racadm.json (reading commands only, cleaned)
IDRAC_HOST=... IDRAC_USERNAME=... IDRAC_PASSWORD=... IDRAC_SSH_HOST_KEY='ssh-ed25519 AAAA...' perl -Ilib -It/lib t/idrac/record-racadm.pl <name>
```

`IDRAC_LIVE_DESTRUCTIVE=1` makes the live suite empty the event log, switch the server
off and on, restart the controller, and (in `t/92-live-racadm.t`) stage a BIOS value, make
and delete a job and attach an image; `IDRAC_LIVE_FORCE_OFF=1` lets it cut the power
where the controller offers no gentle shutdown. Never set either yourself; they hit a
real machine.

A recording is only committed after a person has read it, and with an `expect.json`
beside it that says what the controller lacks (and its `license`); `t/85-fixtures.t` prints
a first version. Never put a password or a host key of a real machine into a recording, a
test or a commit; the recorders hide the host, the user and the password they were given.

`LICENSE` is committed, not generated at build time; re-run `dzil genlicense` and
`git add LICENSE` after changing license, holder or year in `dist.ini`.
