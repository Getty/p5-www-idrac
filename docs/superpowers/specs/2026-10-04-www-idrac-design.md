# WWW::iDRAC – Design

Datum: 2026-10-04
Status: freigegeben am 2026-10-04. Abschnitt 9 nennt, was erst am Gerät entschieden wird.
Plan: `docs/superpowers/plans/2026-10-04-www-idrac-phase-1.md`
Distribution: `WWW-iDRAC` (Repo `p5-www-idrac`), CPAN-fähig, `[@Author::GETTY]`
Zwilling: `Net-Async-iDRAC` (Repo `p5-net-async-idrac`), später, strukturgleich mit `_f`-Methoden.

## 1. Was WWW::iDRAC ist

**WWW::iDRAC ist der Perl-Client für Dells iDRAC: Inventar, Power, Sensoren, Logs und
der Controller selbst, hinter einer Fassade, die nach Fähigkeiten geschnitten ist und
nicht nach Protokollen.**

Es gibt keinen konkreten Anlass, sondern eine Lücke: Auf CPAN existiert keine iDRAC-Dist.
In der Nähe liegen nur `Mojo-Redfish-Client` (0.03 von 2019, generisch, an Mojolicious
gebunden) und `DMTF-WSMan` (2012, verwaist). Ziel ist ein allgemeiner Client, der über
Phasen vollständig wird.

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

Der Aufrufer weiß nicht, über welches Protokoll eine Fähigkeit läuft. In Phase 1 ist das
immer Redfish. Ab Phase 2 schließt ein zweiter Transport die Lücken, die Redfish auf
alten Controllern lässt, ohne dass sich die öffentliche API ändert.

### Die Hardware, gegen die gebaut wird

| Gerät | Generation | Controller |
|---|---|---|
| PowerEdge T330 | 13G | iDRAC 8 |
| PowerEdge R720xd | 12G | iDRAC 7 |

Beide teilen die Firmware-Linie 2.x. Redfish ist dort nur in Teilen vorhanden: Inventar,
Power, Sensoren und Logs ja; Virtual Media einhängen, die meisten Dell-OEM-Actions,
Storage und Firmware-Update im Wesentlichen erst ab iDRAC 9. Diese Grenzen stammen aus
der Dokumentation und werden in Karte 1 am Gerät nachgemessen (Abschnitt 9).

### Was WWW::iDRAC nicht ist

- **Kein generischer Redfish-Client.** Der Redfish-Teil ist intern sauber abgegrenzt und
  ließe sich später als eigene Dist herauslösen. Ohne ein Nicht-Dell-Testgerät wäre eine
  herstellerneutrale Schicht jetzt Spekulation.
- **Kein IPMI.** Wer `ipmitool` braucht, nimmt `ipmitool`.
- **Keine virtuelle Konsole.** KVM/HTML5-Konsole ist keine API.
- **Kein OpenManage-Enterprise-Client.** Die Dist redet mit einem einzelnen iDRAC.
- **Kein Kommandozeilenwerkzeug in Phase 1.**

## 2. Aufbau

```
WWW::iDRAC                    Fassade: host, Zugangsdaten, TLS, ua
  ├─ ->capabilities  WWW::iDRAC::Capabilities   was dieser Controller ist und kann
  ├─ ->system        WWW::iDRAC::System         Inventar und Zustand des Servers
  ├─ ->power         WWW::iDRAC::Power          Schalten und Leistungsaufnahme
  ├─ ->sensors       WWW::iDRAC::Sensors        Temperaturen, Lüfter, Netzteile, Spannungen
  ├─ ->logs          WWW::iDRAC::Logs           System-Event-Log und Lifecycle-Log
  ├─ ->manager       WWW::iDRAC::Manager        der iDRAC selbst
  └─ ->redfish       WWW::iDRAC::Redfish        Transport und Notausgang

WWW::iDRAC::Role::HTTP        build_request / read_response / send_request
WWW::iDRAC::Error             ::Validation, ::Network, ::API, ::Unsupported
```

Form und Namen folgen `WWW::Keycloak`: Moo, eine Klasse pro Belang, ein Paket pro Datei,
eine gemeinsame HTTP-Rolle, `Types::Standard`, `namespace::autoclean`.

**Die Regel, die den Schnitt trägt:** Öffentliche Methoden der Fähigkeits-Klassen geben
normalisierte Perl-Daten zurück (Abschnitt 5), nie rohe Redfish-Dokumente. Nur
`WWW::iDRAC::Redfish` kennt Pfade, `@odata`-Verweise und Redfish-Feldnamen nach außen;
die Fähigkeits-Klassen übersetzen. Damit hängt kein Aufrufer an Redfish-Formen, und ein
zweiter Transport kann in Phase 2 dieselben Daten liefern.

Eine Transport-Abstraktion mit nur einer Implementierung wird in Phase 1 nicht gebaut.
Sie entsteht in Phase 2, wenn der zweite Transport ihre Form vorgibt.

## 3. Fassade

| Attribut | Bedeutung |
|---|---|
| `host` | Pflicht. Name oder Adresse, optional mit `:port`. |
| `username`, `password` | Pflicht. |
| `session` | Standard `1`: Redfish-Session mit Token. `0`: Basic-Auth pro Anfrage. |
| `verify_ssl` | Standard `1`. |
| `ssl_ca_file` | CA oder das selbstsignierte Zertifikat des iDRAC. |
| `ssl_fingerprint` | Zertifikat anpinnen (`sha256$…`), ohne CA. |
| `ssl_opts` | Durchgereicht an `LWP::UserAgent`, für Sonderfälle. |
| `timeout` | Standard 60 Sekunden; iDRACs antworten langsam. |
| `ua` | Eigener `LWP::UserAgent`, überschreibt die TLS-Attribute. |

**TLS.** iDRACs haben fast immer selbstsignierte Zertifikate, ausgestellt auf einen
Namen, der nicht ihre Adresse ist. Die Prüfung ist trotzdem standardmäßig an.
`ssl_fingerprint` ist der Weg für das Werkszertifikat: Ein angepinntes Zertifikat wird
unabhängig vom Namen angenommen. `ssl_ca_file` passt zu einem Controller mit ordentlichem
Zertifikat; allein scheitert es beim Werkszertifikat am Namen. `verify_ssl => 0` ist
möglich, aber eine ausdrückliche Entscheidung des Aufrufers. Das ist
dieselbe Linie wie beim Rex-Host-Key-Muster. Die Dist schaltet von sich aus weder
TLS-Versionen noch Cipher herunter; wer ein altes Gerät nur so erreicht, tut das über
`ssl_opts`.

**Lebensdauer.** `logout` beendet die Session. Der Transport ruft es in `DEMOLISH` als
letzten Versuch auf und schluckt Fehler; so endet die Session mit dem letzten Objekt, das
sie benutzt, auch wenn das nicht die Fassade ist. Das ist nötig, weil ein iDRAC nur wenige gleichzeitige Sessions
zulässt und verwaiste erst nach einem Timeout freigibt.

## 4. Redfish-Transport (`WWW::iDRAC::Redfish`)

```perl
my $doc = $idrac->redfish->get('/redfish/v1/Systems/System.Embedded.1');
$idrac->redfish->post( $path, \%body );
$idrac->redfish->patch( $path, \%body );
$idrac->redfish->delete($path);
my @docs = $idrac->redfish->members( $collection_path, limit => 50 );
```

- **Anmeldung.** Beim ersten Aufruf wird der Service-Root gelesen und der Session-Pfad
  aus `Links.Sessions` genommen, nicht fest verdrahtet (er unterscheidet sich zwischen
  den Generationen). Der Token aus `X-Auth-Token` gilt für alle weiteren Anfragen. Bei
  401 wird einmal neu angemeldet und die Anfrage wiederholt.
- **Navigation.** System, Chassis und Manager werden über die Collections des
  Service-Root gefunden, nicht über feste Namen wie `System.Embedded.1`. Diese
  Wegweiser-Dokumente werden für die Lebensdauer des Objekts gemerkt. Messwerte und
  Zustände werden nie gemerkt.
- **Collections.** `members` gibt die Einträge einer Collection als Dokumente zurück.
  Liefert der Controller sie schon vollständig in `Members`, werden sie so genommen;
  stehen dort nur Verweise, holt `members` jeden einzeln, weil alte Firmware kein
  `$expand` kennt. `limit` begrenzt die Zahl der Einträge und damit der Anfragen.
- **Notausgang.** `->redfish` ist öffentlich und dokumentiert. Was die Fassade noch nicht
  abdeckt, erreicht man darüber, mit rohen Redfish-Dokumenten.

## 5. Fähigkeiten in Phase 1

Rückgaben sind Hashrefs oder Arrayrefs von Hashrefs mit festen Schlüsseln in
`snake_case`. Ein Schlüssel, zu dem der Controller nichts liefert, ist vorhanden und
`undef`. `health` ist überall `ok`, `warning`, `critical` oder `undef`.

### 5.1 `capabilities`

`generation` (7, 8, 9, 10), `model`, `firmware`, `redfish_version`, `license`
(`basic`, `express`, `enterprise`, `datacenter` oder `undef`, wenn nicht lesbar).

`supports($name)` beantwortet, ob eine Fähigkeit auf diesem Controller vorhanden ist. Die
Namen sind die der Methoden (`power.cycle`, `logs.clear_sel`). Die Antwort kommt aus dem,
was der Controller selbst anbietet (vorhandene Ressourcen, `AllowableValues` der
Actions), nicht aus einer Versionstabelle in der Dist.

### 5.2 `system`

| Methode | Rückgabe |
|---|---|
| `info` | `manufacturer`, `model`, `service_tag`, `serial`, `uuid`, `asset_tag`, `hostname`, `bios_version`, `power_state`, `health`, `cpu_count`, `cpu_model`, `memory_gib` |
| `processors` | je CPU: `name`, `model`, `cores`, `threads`, `speed_mhz`, `health` |
| `memory` | je Modul: `name`, `size_mib`, `type`, `speed_mhz`, `manufacturer`, `part_number`, `serial`, `health` |
| `nics` | je Schnittstelle: `name`, `mac`, `speed_mbps`, `link_up`, `health` |

### 5.3 `power`

| Methode | Wirkung |
|---|---|
| `state` | `on` oder `off`; unterwegs nennt der Controller gelegentlich einen Zwischenzustand, der in derselben Form zurückkommt (`powering_on`) |
| `on` | einschalten |
| `off` | sanft herunterfahren; `off( force => 1 )` schaltet hart ab |
| `restart` | sanfter Neustart; `restart( force => 1 )` hart |
| `cycle` | aus und wieder an |
| `wait_for( $state, timeout => 120 )` | fragt `state` ab, bis er erreicht ist; gibt wahr zurück, bei Ablauf der Zeit falsch |
| `consumption` | `watts`, `average_watts`, `min_watts`, `max_watts`, `capacity_watts` |

Schaltende Methoden kehren zurück, sobald der iDRAC den Auftrag angenommen hat. Vor dem
Absenden wird der gewünschte `ResetType` gegen die `AllowableValues` der Action geprüft;
fehlt er, gibt es `Error::Unsupported`, keinen HTTP-Fehler.

### 5.4 `sensors`

| Methode | Rückgabe je Eintrag |
|---|---|
| `temperatures` | `name`, `celsius`, `upper_warning`, `upper_critical`, `lower_warning`, `lower_critical`, `health` |
| `fans` | `name`, `reading`, `units`, `health` |
| `voltages` | `name`, `volts`, `health` |
| `power_supplies` | `name`, `model`, `serial`, `firmware`, `capacity_watts`, `input_volts`, `output_watts`, `health` |

### 5.5 `logs`

| Methode | Wirkung |
|---|---|
| `sel( limit => 50 )` | System-Event-Log, neueste zuerst |
| `lifecycle( limit => 50 )` | Lifecycle-Log, neueste zuerst |
| `clear_sel` | leert das System-Event-Log |

Je Eintrag: `id`, `created`, `severity`, `message`, `message_id`.

### 5.6 `manager`

| Methode | Wirkung |
|---|---|
| `info` | `model`, `firmware`, `health`, `date_time`, `uuid` |
| `network` | `hostname`, `fqdn`, `mac`, `ipv4` (Liste), `ipv6` (Liste), `dns` (Liste) |
| `restart` | startet den iDRAC neu, nicht den Server |

### Nicht in Phase 1

BIOS-Attribute, Job-Queue, Virtual Media, Storage/RAID, Firmware-Update, Benutzer,
Zertifikate, iDRAC-Konfiguration schreiben, Async, CLI.

## 6. Fehler

Alle Fehler sind Objekte, stringifizieren zu ihrer Meldung und werden mit `throw`
geworfen, wie in `WWW::Keycloak`.

| Klasse | Wann | Zusätzlich |
|---|---|---|
| `Error::Validation` | falsche Argumente | |
| `Error::Network` | keine HTTP-Antwort, TLS-Fehler | |
| `Error::API` | iDRAC antwortet mit Fehler | `http_status`, `message_id`, `api_message`, `resolution`; `is_not_found`, `is_unauthorized` |
| `Error::Unsupported` | Fähigkeit fehlt auf diesem Controller | `capability`, `reason` |

`Error::API` liest Redfishs `error.@Message.ExtendedInfo`: `message_id` ist die
Dell-Kennung (z. B. `IDRAC.1.6.SYS403`), `resolution` Dells Handlungsvorschlag.
`Error::Unsupported` werfen nur die Fähigkeits-Klassen: aus der Prüfung vor dem Aufruf
und wenn eine Ressource, die sie selbst ansteuern, auf diesem Controller mit 404
antwortet. Der Notausgang `->redfish` übersetzt nichts; dort bleibt eine 404 ein
`Error::API` mit `is_not_found`.

## 7. Zwilling

`Net::Async::iDRAC` folgt, wenn Phase 1 steht. Dafür gilt schon jetzt: `build_request` und
`read_response` in `Role::HTTP` sind frei von I/O, die Übersetzung von Redfish-Dokumenten
in normalisierte Daten liegt in reinen Funktionen der Fähigkeits-Klassen, und die
Fehlerklassen sind über `api_error_class`/`network_error_class` austauschbar. Der Zwilling
hängt von `WWW-iDRAC` ab und teilt diesen Code, statt ihn zu kopieren.

## 8. Tests

- **Unit-Tests** laufen gegen `t/lib/FakeiDRAC.pm`, einen `LWP::UserAgent`-Ersatz, der
  eine Abbildung von Pfad auf Dokument ausliefert: erfundene Dokumente für die
  Unit-Tests, und die Aufnahmen `t/fixtures/idrac7/redfish.json` und
  `t/fixtures/idrac8/redfish.json` für `t/85-fixtures.t`, das jede lesende Methode gegen
  beide Generationen prüft.
- **Fixtures** nimmt `t/idrac/record.pl` auf: nur `GET`, läuft den Redfish-Baum ab und
  ersetzt vor dem Schreiben Service-Tags, Seriennummern, MACs, IPs, Hostnamen, UUIDs und
  Benutzernamen durch feste Platzhalter. Das Repo wird öffentlich; unbereinigte
  Aufzeichnungen werden nicht committet.
- **Live-Suite** `t/90-live-idrac.t` läuft nur mit `IDRAC_HOST`, `IDRAC_USERNAME`,
  `IDRAC_PASSWORD` (dazu `IDRAC_SSL_FINGERPRINT` oder `IDRAC_VERIFY_SSL=0`) und ist
  lesend. Schaltende Tests (Power, `clear_sel`, `manager->restart`) brauchen zusätzlich
  `IDRAC_LIVE_DESTRUCTIVE=1`, weil sie eine echte Maschine treffen.

Abhängigkeiten: `Moo`, `Type::Tiny`, `LWP::UserAgent`, `LWP::Protocol::https`,
`IO::Socket::SSL`, `HTTP::Message`, `JSON::MaybeXS`, `namespace::autoclean`; für die
Tests zusätzlich `URI`; Perl 5.020.

## 9. Am Gerät zu klären (Karte 1)

Diese Punkte sind keine Lücken im Design, sondern Messungen, die das Design an den
genannten Stellen festlegen. Karte 1 beobachtet beide iDRACs lesend, nimmt die Fixtures
auf und trägt die Ergebnisse hier ein.

| Frage | Folge |
|---|---|
| Firmware-Stand beider Controller; ist Redfish überhaupt vorhanden? | Zu alte Firmware: Update ist Voraussetzung und Handarbeit, keine Aufgabe der Dist. |
| Welche TLS-Versionen und Cipher spricht der Controller? | Geht nur TLS 1.0/1.1: wie oben, Firmware-Update; die Dist bekommt keinen unsicheren Standard. |
| Ist die Lizenzstufe über Redfish lesbar? | Wenn nein, bleibt `license` in Phase 1 `undef` und wird in Phase 2 nachgeliefert. |
| Wie viele Sessions lässt der Controller zu, wie lange leben sie? | Bestätigt oder ändert den Standard `session => 1`. |
| Wo liegen SEL und Lifecycle-Log, kommen Einträge inline oder einzeln? | Legt die Umsetzung von `logs` und `limit` fest. |
| Welche Schlüssel aus Abschnitt 5 liefert iDRAC 7/8 tatsächlich? | Schlüssel ohne Quelle bleiben `undef`; fehlende ganze Ressourcen werden `Unsupported`. |
| WS-Man oder racadm über SSH als zweiter Transport? | Entscheidung für Phase 2. Kriterium: Was deckt BIOS-Attribute, Jobs und Virtual Media auf beiden Geräten ab und liefert strukturierte Daten? |

## 10. Phasen

1. **Anlage.** Dist-Gerüst, Agenten-Team und Board (Abschnitt 11), noch ohne Code.
2. **Karte 1 – beobachten.** Beide iDRACs lesend abfragen, Fixtures aufnehmen, Abschnitt 9
   beantworten, Spec nachschärfen. Der Recorder braucht den Transport; deshalb entstehen
   Fehlerklassen, HTTP-Rolle und Redfish-Transport hier, vor dem Beobachten.
3. **Phase 1 – bauen.** Fassade, `capabilities` und die fünf Fähigkeits-Klassen aus
   Abschnitt 5, Unit-Tests, Fixture-Test über beide Aufnahmen, Live-Suite.
4. **Phase 2 – Lücken auf iDRAC 7/8.** Zweiter Transport, Transport-Abstraktion, BIOS-
   Attribute, Job-Queue, Virtual Media.
5. **`Net::Async::iDRAC`.**
6. **Phase 3 – iDRAC 9/10.** Dell-OEM-Actions, Storage, Firmware-Update; erst mit einem
   solchen Gerät im Zugriff.
