# WWW::iDRAC – Design

Date: 2026-10-04
Status: approved on 2026-10-04. Section 9 names what was decided on the device; phase 2 (racadm over SSH) has been built since 2026-10-14.
Plan: `docs/superpowers/plans/2026-10-04-www-idrac-phase-1.md`
Distribution: `WWW-iDRAC` (repo `p5-www-idrac`), CPAN-ready, `[@Author::GETTY]`
Twin: `Net-Async-iDRAC` (repo `p5-net-async-idrac`), later, structurally identical with `_f` methods.

## 1. What WWW::iDRAC is

**WWW::iDRAC is the Perl client for Dell's iDRAC: inventory, power, sensors, logs and
the controller itself, behind a facade that is cut along capabilities and
not along protocols.**

There is no concrete trigger, but a gap: no iDRAC dist exists on CPAN.
Nearby there are only `Mojo-Redfish-Client` (0.03 from 2019, generic, tied to
Mojolicious) and `DMTF-WSMan` (2012, abandoned). The goal is a general client that becomes
complete over phases.

```perl
my $idrac = WWW::iDRAC->new(
  host        => 'idrac-t330.example.org',
  username    => 'root',
  password    => $ENV{IDRAC_PASSWORD},
  ssl_ca_file => '/etc/ssl/idrac-ca.pem',
);

say $idrac->system->info->{service_tag};
say $_->{name}, ': ', $_->{celsius} for @{ $idrac->sensors->temperatures };

$idrac->power->off;
$idrac->power->wait_for( 'off', timeout => 120 );
```

The caller does not know which protocol a capability runs over. In phase 1 that is
always Redfish. Since phase 2 a second transport, racadm over SSH, closes the gaps
that Redfish leaves on iDRAC 7 and 8 (BIOS attributes, job queue, virtual media, license),
without the public API of the phase 1 classes changing.

### The hardware it is built against

| Device | Generation | Controller |
|---|---|---|
| PowerEdge T330 | 13G | iDRAC 8 |
| PowerEdge R720xd | 12G | iDRAC 7 |

Both share the 2.x firmware line. Redfish is only partially present there: inventory,
power, sensors and logs yes; mounting virtual media, most Dell OEM actions,
storage and firmware update essentially only from iDRAC 9. These limits come from
the documentation and are re-measured on the device in card 1 (section 9).

### What WWW::iDRAC is not

- **Not a generic Redfish client.** The Redfish part is cleanly separated internally and
  could later be extracted as a dist of its own. Without a non-Dell test device a
  vendor-neutral layer would be speculation now.
- **No IPMI.** Whoever needs `ipmitool` uses `ipmitool`.
- **No virtual console.** The KVM/HTML5 console is not an API.
- **Not an OpenManage Enterprise client.** The dist talks to a single iDRAC.
- **No command-line tool in phase 1.**

## 2. Structure

```
WWW::iDRAC                    facade: host, credentials, TLS, ua
  ├─ ->capabilities  WWW::iDRAC::Capabilities   what this controller is and can do
  ├─ ->system        WWW::iDRAC::System         inventory and state of the server
  ├─ ->power         WWW::iDRAC::Power          switching and power consumption
  ├─ ->sensors       WWW::iDRAC::Sensors        temperatures, fans, power supplies, voltages
  ├─ ->logs          WWW::iDRAC::Logs           system event log and lifecycle log
  ├─ ->manager       WWW::iDRAC::Manager        the iDRAC itself
  ├─ ->bios          WWW::iDRAC::Bios           BIOS attributes (racadm)
  ├─ ->jobs          WWW::iDRAC::Jobs           job queue (racadm)
  ├─ ->virtual_media WWW::iDRAC::VirtualMedia   remote image (racadm)
  ├─ ->redfish       WWW::iDRAC::Redfish        transport 1 and escape hatch
  └─ ->racadm        WWW::iDRAC::Racadm         transport 2 (SSH) and escape hatch
                       └─ WWW::iDRAC::Racadm::SSH   the I/O, via Net::OpenSSH

WWW::iDRAC::Role::Transport   transport_name, logout: what both transports share
WWW::iDRAC::Role::HTTP        build_request / read_response / send_request
WWW::iDRAC::Role::Area        unsupported, supports: what every capability class shares
WWW::iDRAC::Role::Capability  Area + Redfish (fetch, resource, linked_path)
WWW::iDRAC::Role::Racadm      Area + racadm (racadm_run, mapping to Unsupported)
WWW::iDRAC::Error             ::Validation, ::Network, ::API, ::Unsupported
```

Shape and names follow `WWW::Keycloak`: Moo, one class per concern, one package per file,
one shared HTTP role, `Types::Standard`, `namespace::autoclean`.

**The rule that carries the cut:** public methods of the capability classes return
normalized Perl data (section 5), never raw Redfish documents. Only
`WWW::iDRAC::Redfish` exposes paths, `@odata` references and Redfish field names;
the capability classes translate. So no caller depends on Redfish shapes, and a
second transport can deliver the same data in phase 2.

A transport abstraction with only one implementation was not built in phase 1.
It came into being in phase 2, when the second transport dictated its shape, and it is small:
`Role::Transport` requires only `transport_name` and `logout`. The capability classes
share `Role::Area` (`unsupported`, `supports`, the `probe_*` convention) and
depend, according to the transport, on `Role::Capability` (Redfish) or `Role::Racadm`. No
class knows both transports; the Redfish classes are unchanged.

## 3. Facade

| Attribute | Meaning |
|---|---|
| `host` | Required. Name or address, optionally with `:port`. |
| `username`, `password` | Required. |
| `session` | Default `1`: Redfish session with token. `0`: basic auth per request. |
| `verify_ssl` | Default `1`. |
| `ssl_ca_file` | CA or the self-signed certificate of the iDRAC. |
| `ssl_fingerprint` | Pin the certificate (`sha256$…`), without a CA. |
| `ssl_opts` | Passed through to `LWP::UserAgent`, for special cases. |
| `timeout` | Default 60 seconds; iDRACs answer slowly. |
| `ua` | Own `LWP::UserAgent`, overrides the TLS attributes. |

**TLS.** iDRACs almost always have self-signed certificates, issued to a
name that is not their address. Verification is on by default anyway.
`ssl_fingerprint` is the way for the factory certificate: a pinned certificate is
accepted regardless of the name. `ssl_ca_file` fits a controller with a proper
certificate; on its own it fails on the factory certificate because of the name. `verify_ssl => 0` is
possible, but an explicit decision of the caller. That is
the same line as with the Rex host-key pattern. The dist on its own downgrades neither
TLS versions nor ciphers; whoever can only reach an old device that way does it via
`ssl_opts`.

**Lifetime.** `logout` ends the session. The transport calls it in `DEMOLISH` as a
last attempt and swallows errors; so the session ends with the last object that
uses it, even if that is not the facade. This is necessary because an iDRAC allows only a few concurrent sessions
and frees orphaned ones only after a timeout.

**SSH (phase 2).** The capabilities via racadm need only the attributes the
Redfish side does not know; everything else is optional:

| Attribute | Meaning |
|---|---|
| `ssh` | Default `1`. `0`: racadm is not used, phase 2 methods are `Unsupported`. |
| `ssh_username`, `ssh_password` | Default: `username`, `password`. Both or neither (otherwise `Validation`). |
| `ssh_port` | Default 22. The port in `host` is the HTTPS port. |
| `ssh_host_key` | Pin the host key (`ssh-ed25519 AAAA…`). |
| `ssh_known_hosts` | A `known_hosts` file; only it counts, the global one is ignored (`GlobalKnownHostsFile=/dev/null`). Not together with `ssh_host_key`. Without either: the SSH client's default files. |
| `ssh_verify_host_key` | Default `1`. `0` accepts any key; not together with the two before. |
| `ssh_opts` | Further `-o Name=Value` for the SSH client, for old algorithms. |

`timeout` also applies to SSH (connection and every command).
| `racadm` | An own transport instead of the built one. |

The same credentials are the default, because an iDRAC serves web and SSH login from
the same user management; whoever separates them uses `ssh_username`/`ssh_password`.
The host key is verified (house pattern as with Rex::LibSSH: strict on, pin or
seed, overridable, never off by itself). `ssh_opts` only do not override what
`Racadm::SSH::options_from` sets (host key verification, login method, one
password attempt); an entry that is not `Name=Value` without spaces and shell characters
throws `Validation`, and only when connecting, not in the constructor. The dist
sets no old algorithms by itself.

## 4. Redfish transport (`WWW::iDRAC::Redfish`)

```perl
my $doc = $idrac->redfish->get('/redfish/v1/Systems/System.Embedded.1');
$idrac->redfish->post( $path, \%body );
$idrac->redfish->patch( $path, \%body );
$idrac->redfish->delete($path);
my @docs = $idrac->redfish->members( $collection_path, limit => 50 );
```

- **Login.** On the first call the service root is read and the session path
  taken from `Links.Sessions`, not hard-wired (it differs between
  the generations). The token from `X-Auth-Token` applies to all further requests. On
  401 it logs in again once and repeats the request.
- **Navigation.** System, chassis and manager are found via the collections of the
  service root, not via fixed names like `System.Embedded.1`. These
  signpost documents are remembered for the lifetime of the object. Readings and
  states are never remembered.
- **Collections.** `members` returns the entries of a collection as documents.
  If the controller already delivers them complete in `Members`, they are taken as is;
  if only references are there, `members` fetches each one individually, because old firmware does not
  know `$expand`. `limit` caps the number of entries and thus of requests.
- **Escape hatch.** `->redfish` is public and documented. What the facade does not cover
  yet can be reached through it, with raw Redfish documents.

## 5. Capabilities

Return values are hashrefs or arrayrefs of hashrefs with fixed keys in
`snake_case`. A key for which the controller delivers nothing is present and
`undef`. `health` is everywhere `ok`, `warning`, `critical` or `undef`.

### 5.1 `capabilities`

`generation` (7, 8, 9, 10), `model`, `firmware`, `redfish_version`, `license`
(`basic`, `express`, `enterprise`, `datacenter` or `undef` if not readable).
Since phase 2 the license comes from `racadm license view` (lines `License Description`,
the highest if there are several) and is read only on `license` or `facts`, never on
`generation`, `model`, `firmware`, `redfish_version`: whoever uses only Redfish opens
no SSH connection; `supports('bios.*')`, `'jobs.*'` and `'virtual_media.*'` open
it as well, because they ask the controller via racadm. `undef` only means: racadm off
(`ssh => 0`), the SSH port refuses the connection (`cause` `refused`), racadm
answers with an error (`Error::API`) or no license is listed. Everything else
is thrown and not remembered: `Validation` and every other `Error::Network` (host key,
login, timeout, unreachable, other). So `capabilities->license` can throw.

`supports($name)` answers whether a capability is present on this controller. The
names are those of the methods (`power.cycle`, `logs.clear_sel`). The answer comes from
what the controller itself offers (present resources, `AllowableValues` of the
actions), not from a version table in the dist.

### 5.2 `system`

| Method | Returns |
|---|---|
| `info` | `manufacturer`, `model`, `service_tag`, `serial`, `uuid`, `asset_tag`, `hostname`, `bios_version`, `power_state`, `health`, `cpu_count`, `cpu_model`, `memory_gib` |
| `processors` | per CPU: `name`, `model`, `cores`, `threads`, `speed_mhz`, `health` |
| `memory` | per module: `name`, `size_mib`, `type`, `speed_mhz`, `manufacturer`, `part_number`, `serial`, `health` |
| `nics` | per interface: `name`, `mac`, `speed_mbps`, `link_up`, `health` |

### 5.3 `power`

| Method | Effect |
|---|---|
| `state` | `on` or `off`; in transit the controller occasionally names an intermediate state, which comes back in the same form (`powering_on`) |
| `on` | power on |
| `off` | graceful shutdown; `off( force => 1 )` cuts power hard |
| `restart` | graceful restart; `restart( force => 1 )` hard |
| `cycle` | off and on again |
| `wait_for( $state, timeout => 120 )` | polls `state` until it is reached; returns true, false when the time runs out |
| `consumption` | `watts`, `average_watts`, `min_watts`, `max_watts`, `capacity_watts` |

Switching methods return as soon as the iDRAC has accepted the order. Before
sending, the requested `ResetType` is checked against the action's `AllowableValues`;
if it is missing, there is `Error::Unsupported`, not an HTTP error.

### 5.4 `sensors`

| Method | Returns per entry |
|---|---|
| `temperatures` | `name`, `celsius`, `upper_warning`, `upper_critical`, `lower_warning`, `lower_critical`, `health` |
| `fans` | `name`, `reading`, `units`, `health` |
| `voltages` | `name`, `volts`, `health` |
| `power_supplies` | `name`, `model`, `serial`, `firmware`, `capacity_watts`, `input_volts`, `output_watts`, `health` |

### 5.5 `logs`

| Method | Effect |
|---|---|
| `sel( limit => 50 )` | system event log, newest first |
| `lifecycle( limit => 50 )` | lifecycle log, newest first |
| `clear_sel` | clears the system event log |

Per entry: `id`, `created`, `severity`, `message`, `message_id`.

### 5.6 `manager`

| Method | Effect |
|---|---|
| `info` | `model`, `firmware`, `health`, `date_time`, `uuid` |
| `network` | `hostname`, `fqdn`, `mac`, `ipv4` (list), `ipv6` (list), `dns` (list) |
| `restart` | restarts the iDRAC, not the server |

### 5.7 `bios` (phase 2, racadm)

Attributes are named `Group.Attribute` as in racadm (`BiosBootSettings.BootMode`).

| Method | Returns / effect |
|---|---|
| `groups` | Arrayref of the group names. Only where the controller lists them (iDRAC 8); iDRAC 7 answers `Unsupported`. |
| `group($group)` | per attribute: `name`, `value` (`undef` if empty), `read_only` |
| `get('Group.Attribute')` | the value; the staged change does not count (unmeasured, see below) |
| `set('Group.Attribute' => $value)` | stages; `name`, `value`, `previous`, `fqdd`, `pending`. Reads first: read-only is `Validation`, unknown is `API` with `is_not_found`, both before writing. The value goes through `Racadm->quote_value`: a value starting with `-` (such as `-1`) is also `Validation`. |
| `commit( reboot => 'none' )` | creates the job (`jobqueue create <fqdd> -r <reboot> -s TIME_NOW`); `job_id`, `reboot_job_id`, `fqdd`. `reboot`: `none` (default), `graceful`, `forced`, `pwrcycle`. If the response contains no `JID_…`, `commit` throws `Error::API` (not `undef`). |

A change takes effect only with a job and a restart of the server. The dist never restarts
the server by itself. `set` and `commit` have not run against any device. Unmeasured and here
only assumed: that `get` does not show a staged change, how `set` recognizes a `pending`
(the word `pending` in the response) and where in the response of `jobqueue create` the
job ID is (the first `JID_…`, the first `RID_…`). `-s TIME_NOW` is unmeasured too:
the recordings contain no `racadm help`, the source of the option is unclear.

### 5.8 `jobs` (phase 2, racadm)

| Method | Returns / effect |
|---|---|
| `list` | per job: `id`, `name`, `status`, `message`, `message_id`, `percent_complete`, `start_time`, `expiration_time`, `finished` |
| `get($id)` | one job, the same keys; unknown jobs are `API` with `is_not_found` |
| `delete($id)` | removes the job; a running one is refused by the controller |
| `wait( $id, timeout => 600, interval => 5 )` | polls `get` until `finished`; returns the job, `undef` when the time runs out |

`id` is `JID_…` or `RID_…`, unchanged from the controller. `finished` means: the status
contains the word `completed`, `failed` or `canceled`/`cancelled` (such as `Completed with
Errors`, `Reboot Failed`); whether the job succeeded is in `status` and `message`. Only
`Completed` is measured (iDRAC 7); the other statuses are unmeasured. `delete` has not run
against any device.

### 5.9 `virtual_media` (phase 2, racadm)

| Method | Returns / effect |
|---|---|
| `status` | `connected`, `share`, `username`, `attach_mode`, `boot_once`, `enabled` (the last three only with a license, otherwise `undef`) |
| `connect( location => …, username => …, password => … )` | mounts an image (`//host/share/a.iso`, `host:/export/a.iso`, `http(s)://…`), returns the status; CIFS needs user and password |
| `disconnect` | unmounts, returns the status |

The password is never returned and appears in no message. `location`, `username`
and `password` go through `Racadm->quote_value`; a URL with `?` or `&` fits none
of the allowed forms and is rejected. `connected` is true if `remoteimage -s`
prints `Remote File Share is Enabled`; only `Disabled` is measured, not the form with
a mounted image. `connect` and `disconnect` have not run against any device.

**The share's password is in the command string** (`remoteimage -c -u … -p … -l …`),
which the SSH client sends to the controller as one argument: it appears in the
arguments of the local `ssh` process (visible via `ps` or `/proc` to other
users of this machine) and on the controller. Unlike the login password, which goes through
the terminal and never appears on a command line. That the controller also requires the license
*Virtual Media* for `remoteimage -c`/`-d` is inferred from the rejection of
`get iDRAC.VirtualMedia` (`SWC0242`, `Required License -- Virtual Media`),
not seen.

### 5.10 Arguments to racadm

racadm reports errors as text with exit status 0, and what its command line does with a
quote, a backslash or shell characters is not known for every firmware.
Therefore every argument consists of letters, digits, spaces and
`_ . : / @ = , + % # -`, otherwise `Validation` (without the value in the message); words with
spaces or `#` go in double quotes. Consequence: a password with `"`,
`\`, `$` and the like cannot be sent. That is the honest limit, no
escaping on suspicion. `Racadm->quote_value` applies to words in the position of a value
(BIOS value, share, user, password) and additionally rejects a word that starts with `-`,
because racadm would read it as an option, even in quotes; a BIOS value like `-1`
therefore cannot be set.

### Not in phase 1 and 2

Storage/RAID, firmware update, users, certificates, writing iDRAC configuration
(except BIOS), async, CLI.

## 6. Errors

All errors are objects, stringify to their message and are thrown with `throw`,
as in `WWW::Keycloak`.

| Class | When | Additionally |
|---|---|---|
| `Error::Validation` | wrong arguments | |
| `Error::Network` | no HTTP response, TLS error; over SSH: connection, host key, login, timeout | `cause` (SSH only: `host_key`, `auth`, `refused`, `unreachable`, `timeout`, `other`; determined from the stderr of the ssh master; only `refused` becomes `Unsupported` in the racadm classes) |
| `Error::API` | iDRAC answers with an error; racadm prints `ERROR:` | `http_status` (`undef` for racadm), `message_id` (`RAC1019`, `SWC0242` …), `api_message`, `resolution`; `is_not_found`, `is_unauthorized` |
| `Error::Unsupported` | capability is missing on this controller | `capability`, `reason` |

`Error::API` reads Redfish's `error.@Message.ExtendedInfo`: `message_id` is the
Dell identifier (e.g. `IDRAC.1.6.SYS403`), `resolution` Dell's suggested action.
`Error::Unsupported` is thrown only by the capability classes: from the check before the call
and when a resource that they address themselves answers with 404 on this controller.
The escape hatch `->redfish` translates nothing; there a 404 stays an
`Error::API` with `is_not_found`.

## 7. Twin

`Net::Async::iDRAC` follows once phase 1 stands. For that, the following already holds: `build_request` and
`read_response` in `Role::HTTP` are free of I/O, the translation of Redfish documents
into normalized data lives in pure functions of the capability classes, and the
error classes are interchangeable via `api_error_class`/`network_error_class`. The twin
depends on `WWW-iDRAC` and shares this code instead of copying it. The same holds for
racadm: `command_from`, `quote`, `error_from`, `blocks_from` and the `*_from` of Bios,
Jobs, VirtualMedia and Capabilities are free of I/O; the I/O lives solely in
`Racadm::SSH` and is interchangeable via the `runner` attribute.

## 8. Tests

- **Unit tests** run against `t/lib/FakeiDRAC.pm`, an `LWP::UserAgent` replacement that
  serves a mapping from path to document: invented documents for the
  unit tests, and the recordings `t/fixtures/idrac7/redfish.json` and
  `t/fixtures/idrac8/redfish.json` for `t/85-fixtures.t`, which checks every reading method against
  both generations.
- **Fixtures** are recorded by `t/idrac/record.pl`: `GET` only, walks the Redfish tree and,
  before writing, replaces service tags, serial numbers, MACs, IPs, hostnames, UUIDs and
  usernames with fixed placeholders. Only the document types the
  tests read are kept, without vendor sections (`Oem`) and without the text of log messages.
  The repo becomes public; unsanitized recordings are not committed, and a
  human reads every recording before it is committed. Next to each recording lies an
  `expect.json` that says what this controller does not have.
- **Live suite** `t/90-live-idrac.t` runs only with `IDRAC_HOST`, `IDRAC_USERNAME`,
  `IDRAC_PASSWORD` (plus `IDRAC_SSL_FINGERPRINT` or `IDRAC_VERIFY_SSL=0`) and is
  read-only. Switching tests (power, `clear_sel`, `manager->restart`) additionally need
  exactly `IDRAC_LIVE_DESTRUCTIVE=1`, because they hit a real machine; cutting power
  hard additionally needs `IDRAC_LIVE_FORCE_OFF=1`.

- **racadm.** `t/lib/FakeRacadm.pm` is the runner of the unit tests: invented values in the
  forms the controllers printed on 2026-10-14, with some state (set, jobqueue
  create/delete, remoteimage), or a recording `t/fixtures/<name>/racadm.json` (mapping
  command line to text; a command not recorded aborts the test).
  `t/idrac/record-racadm.pl` records, read-only (`license view`, `get`, `jobqueue view`,
  `remoteimage -s`), sanitizes with `t/lib/iDRACSanitizeRacadm.pm` and reads the raw
  output, so error texts get into the recording. `t/85-fixtures.t` checks the
  racadm methods against both recordings; `expect.json` knows `license` for that.
  `t/33-racadm-ssh.t` checks the I/O layer against a replacement for Net::OpenSSH.
- **Live, racadm.** `t/92-live-racadm.t`: read-only like the others; writing (setting a BIOS value
  to itself, creating and deleting a job, mounting an image) only with
  `IDRAC_LIVE_DESTRUCTIVE=1`, the image additionally with `IDRAC_LIVE_VMEDIA_LOCATION`.

Dependencies: `Moo`, `Type::Tiny`, `LWP::UserAgent`, `LWP::Protocol::https`,
`IO::Socket::SSL`, `HTTP::Message`, `JSON::MaybeXS`, `namespace::autoclean`, `Net::OpenSSH`
(loaded only when racadm is used) with `IO::Pty` for the password prompt; for the
tests additionally `URI`; Perl 5.020. At runtime also the `ssh` program from OpenSSH.

## 9. To be clarified on the device (card 1)

These points are not gaps in the design, but measurements that pin the design down at the
places named. Card 1 observes both iDRACs read-only, records the fixtures
and enters the results here.

| Question | Consequence |
|---|---|
| Firmware level of both controllers; is Redfish present at all? | Firmware too old: an update is a prerequisite and manual work, not a task of the dist. |
| Which TLS versions and ciphers does the controller speak? | If only TLS 1.0/1.1 works: as above, firmware update; the dist gets no insecure default. |
| Is the license tier readable via Redfish? | If not, `license` stays `undef` in phase 1 and is delivered in phase 2. No (see below); phase 2 delivers it via racadm. |
| How many sessions does the controller allow, how long do they live? | Confirms or changes the default `session => 1`. |
| Where are the SEL and lifecycle log, do entries come inline or individually? | Determines the implementation of `logs` and `limit`. |
| Which keys from section 5 do iDRAC 7/8 actually deliver? | Keys without a source stay `undef`; entire missing resources become `Unsupported`. |
| WS-Man or racadm over SSH as the second transport? | **Decided on 2026-10-14: racadm over SSH.** Measurement and reasoning below. |

### Measured on 2026-10-05

Both devices were recorded strictly read-only (`t/idrac/record.pl`), then
`t/90-live-idrac.t` ran read-only against both. Nothing was switched: both are
production machines.

| Question | PowerEdge R720xd (iDRAC 7) | PowerEdge T330 (iDRAC 8) |
|---|---|---|
| Firmware, Redfish | 2.65.65.65, Redfish 1.4.0 | 2.50.50.50, Redfish 1.0.2 |
| Manager model | `12G Monolithic`, recognized as iDRAC 7 | `13G Monolithic`, recognized as iDRAC 8 |
| TLS | TLS 1.2, ECDHE-RSA-AES256-GCM-SHA384 | TLS 1.2, DHE-RSA-AES256-GCM-SHA384 |
| Service root | 200 with and without trailing slash, no redirect | same |
| License via Redfish | no license document in the tree | same |
| Sessions | `/redfish/v1/Sessions`, timeout 1800 s | same |
| Logs | services `SEL` and `LC` under `LogServices/Sel` and `/Lclog`; entries inline, newest first | same; the key is called `MessageID` here |
| Reset types | `On ForceOff ForceRestart GracefulShutdown PushPowerButton Nmi` | `On ForceOff GracefulRestart PushPowerButton Nmi` |
| Memory collection | present | missing |
| Walked / kept | 193 documents in 98 s / 66 | 56 in 38 s / 40 |
| Unreachable | `Storage/RAID.Integrated.1-1` (404) | `VirtualMedia` (403) |

What follows from this:

- **The factory certificate** can be pinned with `ssl_fingerprint`; that is how the recording and
  live suite ran. The dist needs no lowered TLS default.
- **`license` stayed `undef` in phase 1**; phase 2 reads it via racadm (below).
- **Session login and logout work**; after the runs no session was open on either
  device. How many sessions a controller allows was not pushed to the limit on the
  production devices. Keep-alive held over 193 requests.
- **Keys these controllers do not deliver** are listed per device in
  `t/fixtures/<name>/expect.json`: `fqdn` of the iDRAC (empty), `asset_tag` (not set),
  `link_up` (no `LinkStatus`), on the R720xd also `hostname`, `health` of the
  network interfaces and `output_watts` of the power supplies.
- **Three assumptions of the code were wrong** and are corrected: the name of the
  lifecycle log service (`LC`), the spelling `MessageID`, and the power supply output,
  which the iDRAC 7 names only under `InputRanges`.
- **Switching:** neither offers `power->cycle`. Graceful `off` is missing on the
  T330, graceful `restart` on the R720xd. **Open for Getty:** whether `off` and `restart` there
  should send `PushPowerButton` or the hard form as a substitute, or whether `Unsupported`
  remains the right answer.
- **Second transport:** `VirtualMedia` answers with 403 on the T330, which points to the
  license tier. Confirmed on 2026-10-14: the T330 has an Express license, and
  racadm names `SWC0242` for virtual media. The decision WS-Man or racadm: below.

### Assumptions from the review (2026-10-05)

State after the measurement: the reset types are right for the T330 and not for the R720xd.
`LinkStatus` is missing on both, the memory collection on the T330. `Thermal` and `Power`
deliver the readings directly, the service root answers without a redirect. The rows on 409
and 503 are unchecked, because nothing was switched.

**Switching run on 2026-10-06 against the R720xd (iDRAC 7, 2.65), with Getty's approval.**
`clear_sel`, graceful `off`, `on` and `manager->restart` ran through. Measured:

- After `clear_sel` the iDRAC 7 answers every read of the event log with 500 ("Failed to
  get SEL count") for about a minute while it clears; IPMI reports 0x81 during that time.
  The live suite now waits for it.
- Graceful `off` was reached after about 35 seconds, `on` immediately; the controller was
  back about three minutes after its restart.
- A login that the booting controller still accepts, but whose response no longer
  arrives, remains as an open session on the device until it expires.
- The server did not come up by itself afterwards: with only one powered supply the
  BIOS stops on cold start with "Power required exceeds PSU wattage … F1 to continue"
  (`ErrPrompt=Enabled`). That is a matter of the machine, not the library, but belongs
  checked before every switching run.

Not run: the hard forms (`off( force => 1 )`, `restart( force => 1 )`) and anything
switching on the iDRAC 8.

The review of the built state named assumptions about iDRAC 7/8 with
firmware 2.x from Dell's documentation. They are not measured and not implemented; card 1 checks them against
the recordings.

| Assumption | If it holds |
|---|---|
| Offered reset types are only `On`, `ForceOff`, `GracefulRestart`, `PushPowerButton`, `Nmi` | `power->off`, `restart( force => 1 )` and `cycle` are `Unsupported` on both devices. Getty decides whether `off` should then send `PushPowerButton` when the server is on. |
| `on` or hard `off` in a state that is already reached is answered with 409 | The switching methods should return without sending if the state is already right. |
| `LinkStatus` is missing on the network interfaces | `link_up` is always `undef`; then belongs in `expect.json`. |
| The `Memory` collection is missing on early 2.x firmware | `system->memory` is `Unsupported`; that is already handled. |
| `Thermal` and `Power` contain only references instead of the readings on early 2.x firmware | The sensors would come back as rows full of `undef`; `expect.json` shows it. |
| While the iDRAC restarts, it also answers with 503 | Requests during that time then end in `Error::API`, not only in `Error::Network`; the POD of `manager->restart` would need an addition. |
| The service root `/redfish/v1/` answers with a redirect | The client follows no redirect; the path of the service root would then need adjusting. |

### Phase 2: second transport, measured on 2026-10-14

Both controllers were queried strictly read-only over SSH (nothing set, created, deleted,
mounted; no power switched). Access: user and password as for Redfish, an
`ssh` from OpenSSH 10 with its default algorithms, host key verified against a key fetched with
`ssh-keyscan` (strict on). **No old algorithms were needed.** The
controllers offer `publickey` and `keyboard-interactive`, not `password`: a client that
only tries `password` fails with `Permission denied`; Net::OpenSSH answers the
password prompt of `keyboard-interactive` via its terminal. The exit status of
`ssh ... racadm ...` is always 0, even on an error: errors are only in the text.

| Question | PowerEdge R720xd (iDRAC 7, FW 2.65) | PowerEdge T330 (iDRAC 8, FW 2.50) |
|---|---|---|
| SSH port 22, `racadm getversion` | yes | yes |
| `racadm license view` | tree with tabs; `License Description = iDRAC7 Enterprise License` | `... iDRAC8 Express License` |
| `racadm get BIOS` (group list) | `ERROR: Unable to perform requested operation.` | 13 group names, one per line |
| `racadm get BIOS.<Group>` | yes, `[Key=BIOS.Setup.1-1#<Group>]`; the recordings contain no `#Name=Value` entry, that `#` means read-only is unmeasured | same |
| `racadm get BIOS.<Group>.<Attr>` | yes, one entry | same |
| Unknown group / attribute | `ERROR: RAC1020` / `ERROR: RAC1019` | same |
| `racadm jobqueue view` | header line, then `[Job ID=JID_…]` blocks with `Key=Value`; one completed job | only the header line (empty queue) |
| `racadm jobqueue view -i <id>` | one block under `---- JOB ----` | unknown ID: `RAC992: Invalid job` without `ERROR:` |
| `racadm remoteimage -s` | `Remote File Share is Disabled` + `UserName`/`Password`/`ShareName` | same |
| `racadm get iDRAC.VirtualMedia` | `Attached`, `BootOnce`, `Enable`, ... | `ERROR: SWC0242 : A required license is missing or expired.` + `Required License -- Virtual Media` |
| `racadm help remoteimage` / `jobqueue` / `set` | usage and options (`-c -u -p -l`, `-d`, `-s`; `jobqueue create <fqdd> -r none\|pwrcycle\|graceful\|forced`, `delete -i`). The code additionally sends `-s TIME_NOW` to `jobqueue create` (in `commit`); that is not in this summary and is unmeasured. | same |

**Decision: racadm over SSH.**

- **Structured data without XML.** The output is Key=Value in `[Key=...]` and
  `[Job ID=...]` blocks with fixed names; a parser is a handful of pure functions.
  WS-Man would mean SOAP/XML envelopes, namespaces and enumeration contexts, to be verified on the R720xd and
  the T330 against two firmware levels, and the dist would have `DMTF-WSMan`
  (2012, abandoned) as its only orientation.
- **Covers everything phase 2 wants.** Reading and setting BIOS (`get`/`set`), job queue
  (`jobqueue view/create/delete`), virtual media (`remoteimage`), license (`license view`)
  worked on both devices or reported the license as the reason.
- **The same credentials**, no further port, no further TLS configuration.
- **Costs:** the responses are slow (seconds per command; one run of the read-only
  live suite 60 to 100 s), SSH is a second service that must be switched on on the iDRAC
  and allows only a few sessions, and errors are text, not status. The
  last is caught by `Racadm::error_from` (it searches for `ERROR:` or a failed line with
code in the whole response, not only in the first line), the second is handled by closing the
connection in `DEMOLISH`, in the process that opened it; a child process after
`fork` leaves the parent process's connection alone. A command that ends with a status
other than 0 does not drop the connection; its output goes through `error_from`.

**SSH library: Net::OpenSSH.** Installed, pure Perl, and it drives the machine's
`ssh`: algorithms, host key verification (`known_hosts`, `StrictHostKeyChecking`) and
`ssh_config` are those of the maintained OpenSSH, not an imitation. It answers the
password prompt via a terminal (`IO::Pty`), so never on a command line. That
applies to the login password; the password of a share (`virtual_media->connect`) is
in the command string (section 5.9).
`Net::SSH2` (libssh2) is not installed here and needs a C library,
`Rex::LibSSH` is tailored to Rex. Downside: an `ssh` program is a runtime prerequisite.

**Host key.** Strict on. `ssh_host_key` pins a key (the dist writes a temporary
`known_hosts` with only it), `ssh_known_hosts` names a file that alone applies (the global `known_hosts` is
ignored), otherwise the SSH client's default files apply; `ssh_verify_host_key => 0` is the explicit decision of the caller
and not allowed together with the other two. One login attempt per connection
(`NumberOfPasswordPrompts=1`), so a wrong password does not hit the controller
multiple times.

**Not measured** (not run, only derived from `racadm help` of both controllers and
the response forms): `racadm set BIOS...`, `jobqueue create`, `jobqueue delete`,
`remoteimage -c`/`-d`, the form of `remoteimage -s` with a mounted image, the response
to `set` and `jobqueue create` (the dist searches it for `pending`, `JID_…`, `RID_…`), jobs
in state `Running`/`Scheduled` and in general all job statuses except `Completed`
(`Completed with Errors`, `Failed`, `Reboot Failed`, cancelled are assumed), several
licenses, and anything writing on the iDRAC 8. Also not seen: that `get` does not show a
staged BIOS attribute, how `set` recognizes a `pending`, where `commit` finds the
job ID (without `JID_…` `commit` throws `Error::API`), the form of `remoteimage -s` with
an image (`connected` is true on `Remote File Share is Enabled`), the `#` character for
read-only attributes (the recordings have none), and that `remoteimage -c`/`-d`
need the license *Virtual Media*: that is inferred from the rejection of `get
iDRAC.VirtualMedia` (`SWC0242`), not seen. The texts with which the
SSH client reports errors were only checked against a closed local port and a
name that does not resolve (`cause` `refused`, `unreachable`), not against an
iDRAC; `host_key`, `auth`, `timeout` and the other patterns have not been seen on a
controller. `racadm get BIOS` on the iDRAC 7 (no group directory) is measured and
`bios.groups` there is `Unsupported`. How the controllers' racadm parser handles quotes
and backslashes is not measured; therefore the dist does not allow such characters in
arguments (section 5.10).

## 10. Phases

1. **Setup.** Dist scaffold, agent team and board (section 11), still without code.
2. **Card 1 – observe.** Query both iDRACs read-only, record fixtures, answer section 9,
   sharpen the spec. The recorder needs the transport; therefore error classes,
   HTTP role and Redfish transport come into being here, before observing.
3. **Phase 1 – build.** Facade, `capabilities` and the five capability classes from
   section 5, unit tests, fixture test over both recordings, live suite.
4. **Phase 2 – gaps on iDRAC 7/8. Built on 2026-10-14.** Second transport (racadm
   over SSH, section 9), transport abstraction (`Role::Transport`, `Role::Area`),
   `Racadm`/`Racadm::SSH`, the capabilities `bios`, `jobs`, `virtual_media` and the
   license in `capabilities`, unit tests against `FakeRacadm`, recordings
   `racadm.json` per generation, read-only live suite `t/92-live-racadm.t`. Run read-only against both
   devices; writing (`set`, `commit`, `jobs->delete`,
   `virtual_media->connect`/`disconnect`) is behind
   `IDRAC_LIVE_DESTRUCTIVE=1` in the live suite and has not run against any device.
5. **`Net::Async::iDRAC`.**
6. **Phase 3 – iDRAC 9/10.** Dell OEM actions, storage, firmware update; only with such a
   device in reach.
