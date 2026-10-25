# WWW-iDRAC House Rules

The shared house rules come from skilletor — bundle `getty-cpan-dist@getty`: engineering
discipline, the delegation lock, the publish gate, karr coordination, CPAN release. They load
as `.claude/rules/.local.*.md`; if they are missing, run `skilletor sync` and publish nothing
until they load. This file adds what is true only here, and wins where it differs.

## What this repo is

Perl client for Dell iDRAC — inventory, power, sensors, logs, BIOS, jobs and virtual media.
Read first: the callers and the sibling module (`WWW::iDRAC::Redfish` ↔ the capability
classes).

## Agent team

| Task | Agent |
|---|---|
| Implement / refactor / debug behavior-relevant code | `www-idrac-worker` (default) |
| Write/extend tests | `www-idrac-test-writer` |
| Write/maintain POD | `www-idrac-doc-writer` |
| Commits, `Changes`, card → done, pre-release audit | `www-idrac-release-manager` |
| Read-only research, audit, gap analysis | `www-idrac-worker` ("read-only, change nothing") |

Behavior-relevant = runtime behavior, the public API (`WWW::iDRAC`, `::Redfish`, `::System`,
`::Power`, `::Sensors`, `::Logs`, `::Manager`, `::Capabilities`, `::Racadm`, `::Racadm::SSH`,
`::Bios`, `::Jobs`, `::VirtualMedia`), the fixed return keys, error handling, tests,
performance. Pure prose docs and `Changes` notes are not.

## Hazards — the short form (mechanism and background: skill `www-idrac-core`)

- **Fixtures are public.** Nothing recorded from a real controller is committed before it went
  through `iDRACSanitize` and a person has read it.
- **Live tests hit a real management controller.** Opt-in via
  `IDRAC_HOST`/`IDRAC_USERNAME`/`IDRAC_PASSWORD`, read-only. Never run them uncontrolled or in a
  fanned-out context; a default `prove -lr t` must pass with them skipped.
- **Never set `IDRAC_LIVE_DESTRUCTIVE=1`** — it switches the machine off and restarts its
  controller. Only the maintainer runs that part.
- **An iDRAC allows only a few sessions.** Code that logs in must end its session; a test that
  leaves one open is a defect.
- **Translation stays apart from I/O** — keep the `*_from` functions and `Role::HTTP`'s
  `build_request`/`read_response` free of I/O.
- **Nothing about the controller comes from memory** — iDRAC facts come from a recorded
  controller or Dell's documentation; the real answers live in `t/fixtures/`.
- **Always `prove -lr t`, never plain `prove -l t/`** — the plain runner is non-recursive and
  skips the subdir tests silently.

## Perl specifics — reference, don't restate

Module loading, Moo patterns, dependency pinning, `[@Author::GETTY]` release metadata, POD
directives and house style live in skills `getty-perl-core`, `getty-perl-moo`,
`perl-release-dist-ini`, `getty-perl-release-author-getty` and `www-idrac-core` (force-loaded
for `www-idrac-*` agents).
