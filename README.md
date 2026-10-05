# WWW-iDRAC

Perl client for the management controller of Dell PowerEdge servers: inventory, power,
sensors, logs and the controller itself. The methods are cut by what you want to know or
do, not by protocol, and return plain hashes with fixed keys.

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

$idrac->logout;
```

## What is in it

| | |
|---|---|
| `$idrac->capabilities` | generation, model, firmware, Redfish version; `supports('power.cycle')` |
| `$idrac->system` | `info`, `processors`, `memory`, `nics` |
| `$idrac->power` | `state`, `on`, `off`, `restart`, `cycle`, `wait_for`, `consumption` |
| `$idrac->sensors` | `temperatures`, `fans`, `voltages`, `power_supplies` |
| `$idrac->logs` | `sel`, `lifecycle`, `clear_sel` |
| `$idrac->manager` | `info`, `network`, `restart` |
| `$idrac->redfish` | `get`, `post`, `patch`, `delete`, `members`: raw Redfish, for everything else |

Everything goes over Redfish in this version. What a controller offers depends on its
generation, firmware and license; a method it cannot serve throws
`WWW::iDRAC::Error::Unsupported` before anything is sent. Everything that reads has
run against an iDRAC 7 (PowerEdge R720xd, firmware 2.65) and an iDRAC 8 (PowerEdge T330,
firmware 2.50). Of the methods that switch something, `clear_sel`, gentle `off`, `on`
and `manager->restart` have run against the iDRAC 7; **the forced forms, and all
switching on an iDRAC 8, have not been run against hardware yet.** Neither of the two
offers a power cycle; the T330 offers no gentle `off`, the R720xd no gentle `restart`.

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

The client logs in once and ends its session when it goes away. An iDRAC allows only a
few sessions at a time, so call `$idrac->logout` when you are done.

## License

This library is free software; you can redistribute it and/or modify it under the same
terms as Perl itself.
