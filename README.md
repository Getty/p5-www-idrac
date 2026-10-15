# WWW-iDRAC

Perl client for the management controller of Dell PowerEdge servers: inventory, power,
sensors, logs, the controller itself, and, on iDRAC 7 and 8, BIOS attributes, the job queue
and virtual media. The methods are cut by what you want to know or do, not by protocol,
and return plain hashes with fixed keys.

```perl
use WWW::iDRAC;

my $idrac = WWW::iDRAC->new(
  host            => 'idrac-t330.example.org',
  username        => 'root',
  password        => $ENV{IDRAC_PASSWORD},
  ssl_fingerprint => 'sha256$5f2c...',
);

print $idrac->system->info->{service_tag}, "\n";
print $_->{name}, ': ', $_->{celsius} // '-', "\n" for @{ $idrac->sensors->temperatures };

$idrac->power->off;
$idrac->power->wait_for( 'off', timeout => 300 );

# what Redfish lacks on an iDRAC 7 or 8 goes over SSH, with racadm
print $idrac->capabilities->license // '?', "\n";   # undef if SSH is off or closed; a failed login throws
print $idrac->bios->get('BiosBootSettings.BootMode'), "\n";
print $_->{id}, ' ', $_->{status}, "\n" for @{ $idrac->jobs->list };

$idrac->logout;
```

## What is in it

| | |
|---|---|
| `$idrac->capabilities` | generation, model, firmware, Redfish version, license (over racadm); `supports('power.cycle')` |
| `$idrac->system` | `info`, `processors`, `memory`, `nics` |
| `$idrac->power` | `state`, `on`, `off`, `restart`, `cycle`, `wait_for`, `consumption` |
| `$idrac->sensors` | `temperatures`, `fans`, `voltages`, `power_supplies` |
| `$idrac->logs` | `sel`, `lifecycle`, `clear_sel` |
| `$idrac->manager` | `info`, `network`, `restart` |
| `$idrac->bios` | racadm: `groups`, `group`, `get`, `set` (staged; not run against hardware), `commit` (creates the job; not run against hardware) |
| `$idrac->jobs` | racadm: `list`, `get`, `delete` (not run against hardware), `wait` |
| `$idrac->virtual_media` | racadm: `status`, `connect`, `disconnect` (the last two not run against hardware) |
| `$idrac->redfish` | `get`, `post`, `patch`, `delete`, `members`: raw Redfish, for everything else |
| `$idrac->racadm` | `run`: what racadm printed, for everything else |

System, power, sensors, logs and the controller go over Redfish; BIOS attributes, jobs,
virtual media and the license go over racadm on the SSH service of the controller, because
an iDRAC 7 and 8 do not offer them over Redfish. What a controller offers depends on its
generation, firmware and license; a method it cannot serve throws
`WWW::iDRAC::Error::Unsupported` before anything is sent. Everything that reads has
run against an iDRAC 7 (PowerEdge R720xd, firmware 2.65) and an iDRAC 8 (PowerEdge T330,
firmware 2.50). Of the methods that switch something over Redfish, `clear_sel`, gentle
`off`, `on` and `manager->restart` have run against the iDRAC 7; **the forced forms, and
all switching on an iDRAC 8, have not been run against hardware yet, and nothing that
writes over racadm has** (`bios->set`/`commit`, `jobs->delete`,
`virtual_media->connect`/`disconnect`). Neither of the two
offers a power cycle; the T330 offers no gentle `off`, the R720xd no gentle `restart`.

## BIOS, jobs and virtual media over SSH

These three and the license are served over racadm through SSH:

```perl
my $idrac = WWW::iDRAC->new(
  host => 'idrac-t330.example.org', username => 'root', password => $ENV{IDRAC_PASSWORD},
  ssl_fingerprint => 'sha256$5f2c...',
  ssh_host_key    => 'ssh-ed25519 AAAA...',     # or ssh_known_hosts => '/path/known_hosts'
);

$idrac->bios->set( 'BiosBootSettings.BootMode' => 'Uefi' );     # staged: pending, nothing changes yet
my $job = $idrac->bios->commit;                                  # the job; no restart unless reboot => 'graceful' ...
my $done = $idrac->jobs->wait( $job->{job_id}, timeout => 900 ); # after the next restart

$idrac->virtual_media->connect( location => 'https://images.example.org/rescue.iso' );
$idrac->virtual_media->disconnect;
```

**Needs.** The SSH service switched on at the iDRAC, the `ssh` program of OpenSSH on the
machine that runs the code, and [Net::OpenSSH](https://metacpan.org/pod/Net::OpenSSH) with
`IO::Pty` for the password prompt (both are in `cpanfile`). The login is the one for Redfish
unless `ssh_username` and `ssh_password` (both or neither) say otherwise; the port is 22
unless `ssh_port` does. `timeout` applies to SSH as well. `ssh => 0` says racadm is not to
be used: the racadm methods are `Unsupported` and no connection is made. Nothing opens an
SSH connection until a racadm method is called, `capabilities->supports('bios.*')`,
`'jobs.*'` or `'virtual_media.*'` is asked, or the license is read; `generation`, `model`,
`firmware` and everything over Redfish never do. racadm is slow: a command takes seconds,
and `bios->set` reads the attribute first.

**Host key.** It is checked, always, unless you turn it off. Pin it with `ssh_host_key`
(`ssh-keyscan -t ed25519 idrac-t330.example.org` prints it; leave out the first column),
give a `known_hosts` file with `ssh_known_hosts` (then only that file counts, the global
one is ignored), or rely on the default `known_hosts` files of the SSH client. The two
options exclude each other. A key it does not know ends the connection with a
`WWW::iDRAC::Error::Network` whose `cause` is `host_key`; the other causes are `auth`,
`refused` (nothing on the port, shown as `Unsupported`), `unreachable` (no route, name
does not resolve, connect timed out), `timeout` and `other`, worked out from what the ssh
client printed (tried against a closed local port and an unresolvable name, not against an
iDRAC). `ssh_verify_host_key => 0` accepts any key and is your decision, not
a default. The client makes one login attempt per connection, so a wrong password counts
once against the lockout of the controller. The dist sets no old algorithms; a controller
that needs one gets it through `ssh_opts => ['KexAlgorithms=+...']`, which cannot override
the options the dist fixes. The two controllers measured below needed none.

**License.** `bios` and `jobs` need none that was found; `virtual_media->connect` and
`disconnect` need the license for virtual media (racadm prints `Required License -- Virtual
Media`), which an iDRAC 8 with an Express license does not have: `racadm get
iDRAC.VirtualMedia` answers `SWC0242` there, shown as `Unsupported`. That `remoteimage -c`
and `-d` need it as well is inferred from that refusal, not seen. `virtual_media->status`
reads without. `$idrac->capabilities->license` says which license the controller has; it is
`undef` where `ssh => 0`, the SSH port is closed or racadm answers with an error, and a
refused login, an unknown host key or a timeout is thrown and not remembered.

**What was measured, and what was not.** On 2026-10-14, reading only, against an iDRAC 7
(PowerEdge R720xd, firmware 2.65, Enterprise license) and an iDRAC 8 (PowerEdge T330,
firmware 2.50, Express license): `license view`, `get BIOS`, `get BIOS.<group>` and one
attribute, `jobqueue view` (with an entry on the iDRAC 7, empty on the iDRAC 8), `jobqueue
view -i`, `remoteimage -s` and `get iDRAC.VirtualMedia`. The iDRAC 7 does not list its BIOS
groups (`bios->groups` is `Unsupported` there) but serves each one by name. **Nothing that
writes over racadm has run against hardware**: `bios->set` and `commit`, `jobs->delete`,
and `virtual_media->connect` and `disconnect` follow `racadm help` of the two controllers
and the shape of what they print, and are only tested against a fake. Never seen: the
status of an attached image (`connected` is true on `Remote File Share is Enabled`), what
racadm prints after `set` and `jobqueue create` (whether `set` reports `pending` and
whether `commit` finds a `JID_`, which it throws `WWW::iDRAC::Error::API` without), that
`bios->get` does not show a staged change, the read-only marker `#` of an attribute (the
recordings hold none), and job statuses other than `Completed`. The live suite `t/92-live-racadm.t` reads; its writing part needs
`IDRAC_LIVE_DESTRUCTIVE=1` and is for the maintainer.

**Arguments.** A value racadm is sent may hold letters, digits, space and
`_ . : / @ = , + % # -`. A quote, a backslash, `$` or the like is refused with
`WWW::iDRAC::Error::Validation` before anything is sent (so is such a password for a CIFS
share): what racadm does with them is not known for every firmware, and escaping on a guess
would be worse than saying no. A value that starts with `-` (a BIOS value such as `-1`,
a location, a user, a password) is refused too, because racadm would read it as an option;
and `virtual_media->connect` refuses a URL with `?` or `&`. **The password of a share is
not hidden on your machine**: unlike the login, it is part of the racadm command string,
so it shows in the arguments of the local `ssh` process (`ps`, `/proc`) to other users
there, and on the controller.

## Certificates

An iDRAC ships with a self-signed certificate under a name that is not its address.
Verification is on by default; pin the certificate with `ssl_fingerprint`:

```bash
openssl s_client -connect idrac-t330.example.org:443 </dev/null 2>/dev/null \
  | openssl x509 -noout -fingerprint -sha256 | sed 's/.*=//; s/://g' | tr A-F a-f
```

and pass the result as `'sha256$<digits>'`. `ssl_ca_file` fits a controller with a proper
certificate, `verify_ssl => 0` turns the check off.

## Sessions

The client logs in once and ends its session when it goes away, and closes its SSH
connection the same way; only in the process that made them, a forked child leaves
those of its parent alone. An iDRAC allows only a few sessions of either kind at a time, so
call `$idrac->logout` when you are done. A process that dies
without going through the destructor — `kill -9`, an unhandled signal, a panic in a
dependency — leaves the session open until the controller times it out. Catch what you
can and call `logout` before you exit.

## License

This library is free software; you can redistribute it and/or modify it under the same
terms as Perl itself.
