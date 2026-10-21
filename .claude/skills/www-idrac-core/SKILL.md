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
- **Fixtures are public.** The recorder keeps only the kinds of document the tests read;
  those go through `iDRACSanitize` and are read by a person before they are committed.
  No service tag, serial number, MAC, address, host name or user name. Widening what is
  kept (`%KEEP` in `t/lib/iDRACRecorder.pm`) means reading what that kind of document
  holds first.
- **Every recording has an `expect.json`** saying what that controller lacks. A key that
  is `undef` in every row is either listed there or a bug.
- **A session is ended by whoever opened it**: on `logout`, when the transport goes away,
  and at the end of the program. Nothing may leave one behind.
- **TLS verification is on by default**, and the dist never lowers TLS versions or ciphers.
- **The password is in no error message and no fixture.**

## Hazards — the mechanisms behind the short rules

**Live tests hit a real server's management controller.** `t/90-live-idrac.t` is opt-in:
it runs only when `IDRAC_HOST`, `IDRAC_USERNAME` and `IDRAC_PASSWORD` are set, and it
only reads. It still talks to a machine that other people use, so it is never run
uncontrolled and never in a fanned-out or parallel context. The default `prove -lr t`
must pass with the live suite skipped — a run that only works with the environment set
is not a green run.

**`IDRAC_LIVE_DESTRUCTIVE=1` switches the machine off** and restarts its controller.
An agent never sets it; only the maintainer runs that part. The trap: the flag reads
like a harmless test switch, and one accidental export takes a real server down.

**An iDRAC allows only a few sessions.** The controller counts them and refuses new
logins. Code that logs in must end its session; a test that leaves one open is a defect
that only shows up later — as the next test failing to log in.

**Translation apart from I/O is what makes the async twin possible.** The `*_from`
functions and `Role::HTTP`'s `build_request`/`read_response` stay free of I/O: the
`Net::Async::iDRAC` twin is planned and reuses them. A translation that quietly opens a
session or does a request cannot be reused.

**iDRAC facts come from a recorded controller or Dell's documentation**, never from
memory. Resource paths and field names differ between generations and firmware
versions, so what the real ones answer lives in `t/fixtures/`. A path written from
memory passes the fake controller and 404s on real hardware.

**The test runner trap: plain `prove -l t/` is non-recursive.** It skips the subdir
tests silently — the suite reports green without ever running them. Always `prove -lr t`.

## Tests

`prove -lr t`. Unit tests run against `FakeiDRAC`, an `LWP::UserAgent` that serves a map
of path to document. `t/85-fixtures.t` runs every reading method against every recorded
controller. `t/90-live-idrac.t` needs `IDRAC_HOST`, `IDRAC_USERNAME`, `IDRAC_PASSWORD` and
only reads; `IDRAC_LIVE_DESTRUCTIVE=1` switches a real machine and is never set by an
agent.

## Recording a controller

`t/idrac/record.pl` writes `t/fixtures/<name>/redfish.json` from a real controller. The
chain behind it, and it is a chain with people in it:

- `%KEEP` in `t/lib/iDRACRecorder.pm` decides which kinds of document are kept at all.
  Widening it means reading what that kind of document holds first — the recorder
  cannot know what a customer put into their own chassis.
- `iDRACSanitize` strips what must not leave the machine: no service tag, no serial
  number, no MAC, no address, no host name, no user name.
- A person reads the result before it is committed. A recorded fixture is public — it
  ships with the distribution.
- Every recording gets an `expect.json` naming what that controller does not have. A key
  that is `undef` in every row is either listed there or a bug in the client.

## Related

- `~/dev/p5-www-keycloak` — `WWW::Keycloak`, the shape this distribution follows.
- `Net::Async::iDRAC` — the planned async twin; it reuses the `*_from` translations,
  which is why they stay free of I/O.

