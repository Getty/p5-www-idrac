---
name: www-idrac-core
description: Use when working on WWW::iDRAC — the capability facade, the Redfish transport, the fixed return keys, Unsupported errors, the recorded fixtures or the live suite.
---

# WWW::iDRAC core

Synchronous Perl client for Dell iDRAC. Shape follows `WWW::Keycloak`
(`~/dev/p5-www-keycloak`): Moo, one class per concern, one package per file, a shared
HTTP role, error objects. The design is
`docs/superpowers/specs/2026-10-04-www-idrac-design.md`, the plan
`docs/superpowers/plans/2026-10-04-www-idrac-phase-1.md`.

## Layout

- `WWW::iDRAC` — facade: host, credentials, TLS options, the user agent; lazy `redfish`,
  `capabilities`, `system`, `power`, `sensors`, `logs`, `manager`.
- `WWW::iDRAC::Redfish` — transport and documented way out. Session login, one re-login
  on 401, `members`, `locate`. Ends its session in `DEMOLISH`.
- `WWW::iDRAC::System`, `::Power`, `::Sensors`, `::Logs`, `::Manager` — capability
  classes, consuming `WWW::iDRAC::Role::Capability`.
- `WWW::iDRAC::Capabilities` — facts and `supports('area.method')`.
- `WWW::iDRAC::Util` — pure translations. `WWW::iDRAC::Role::HTTP` — sending.
- `WWW::iDRAC::Error::{Validation,Network,API,Unsupported}`.

## Invariants

- **Capability classes return translated data, never Redfish documents.** Hashes with
  fixed `snake_case` keys; a key without a source is present and `undef`; `health` is
  `ok`, `warning`, `critical` or `undef`. The keys are listed once, in
  `t/lib/iDRACShapes.pm`. Changing a key is an API change.
- **Only `WWW::iDRAC::Redfish` knows paths.** System, chassis and manager are found
  through `locate`, parts through the links of a document. No `System.Embedded.1` in
  `lib/`.
- **`Unsupported` comes before anything is sent**, and only from capability classes. The
  transport translates nothing; a 404 there stays an `Error::API`.
- **Every public method `x` of a capability class has a `probe_x`**, and `supports` is
  built on those. A new method without its probe is invisible to `supports`.
- **Translation is separate from I/O**: `info_from`, `entry_from` and their kin take a
  document and return the hash. The async twin reuses them.
- **Nothing about the controller is coded from memory.** What a real iDRAC answers is in
  `t/fixtures/<name>/redfish.json`, recorded with `t/idrac/record.pl`. The default
  documents of `t/lib/FakeiDRAC.pm` are invented and say so.
- **Fixtures are public.** They go through `iDRACSanitize` and are read by a person
  before they are committed. No service tag, serial number, MAC, address or host name.
- **TLS verification is on by default**, and the dist never lowers TLS versions or ciphers.
- **The password is in no error message and no fixture.**

## Tests

`prove -lr t`. Unit tests run against `FakeiDRAC`, an `LWP::UserAgent` that serves a map
of path to document. `t/85-fixtures.t` runs every reading method against every recorded
controller. `t/90-live-idrac.t` needs `IDRAC_HOST`, `IDRAC_USERNAME`, `IDRAC_PASSWORD` and
only reads; `IDRAC_LIVE_DESTRUCTIVE=1` switches a real machine and is never set by an
agent.
