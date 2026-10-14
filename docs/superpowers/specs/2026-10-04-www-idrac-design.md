# WWW::iDRAC – Design

Datum: 2026-10-04
Status: freigegeben am 2026-10-04. Abschnitt 9 nennt, was am Gerät entschieden wurde; Phase 2 (racadm über SSH) ist seit 2026-10-14 gebaut.
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
immer Redfish. Seit Phase 2 schließt ein zweiter Transport, racadm über SSH, die Lücken,
die Redfish auf iDRAC 7 und 8 lässt (BIOS-Attribute, Job-Queue, Virtual Media, Lizenz),
ohne dass sich die öffentliche API der Phase-1-Klassen ändert.

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
  ├─ ->bios          WWW::iDRAC::Bios           BIOS-Attribute (racadm)
  ├─ ->jobs          WWW::iDRAC::Jobs           Job-Queue (racadm)
  ├─ ->virtual_media WWW::iDRAC::VirtualMedia   Remote-Image (racadm)
  ├─ ->redfish       WWW::iDRAC::Redfish        Transport 1 und Notausgang
  └─ ->racadm        WWW::iDRAC::Racadm         Transport 2 (SSH) und Notausgang
                       └─ WWW::iDRAC::Racadm::SSH   die I/O, über Net::OpenSSH

WWW::iDRAC::Role::Transport   transport_name, logout: was beide Transporte teilen
WWW::iDRAC::Role::HTTP        build_request / read_response / send_request
WWW::iDRAC::Role::Area        unsupported, supports: was jede Fähigkeits-Klasse teilt
WWW::iDRAC::Role::Capability  Area + Redfish (fetch, resource, linked_path)
WWW::iDRAC::Role::Racadm      Area + racadm (racadm_run, Abbildung auf Unsupported)
WWW::iDRAC::Error             ::Validation, ::Network, ::API, ::Unsupported
```

Form und Namen folgen `WWW::Keycloak`: Moo, eine Klasse pro Belang, ein Paket pro Datei,
eine gemeinsame HTTP-Rolle, `Types::Standard`, `namespace::autoclean`.

**Die Regel, die den Schnitt trägt:** Öffentliche Methoden der Fähigkeits-Klassen geben
normalisierte Perl-Daten zurück (Abschnitt 5), nie rohe Redfish-Dokumente. Nur
`WWW::iDRAC::Redfish` kennt Pfade, `@odata`-Verweise und Redfish-Feldnamen nach außen;
die Fähigkeits-Klassen übersetzen. Damit hängt kein Aufrufer an Redfish-Formen, und ein
zweiter Transport kann in Phase 2 dieselben Daten liefern.

Eine Transport-Abstraktion mit nur einer Implementierung wurde in Phase 1 nicht gebaut.
Sie ist in Phase 2 entstanden, als der zweite Transport ihre Form vorgab, und ist klein:
`Role::Transport` verlangt nur `transport_name` und `logout`. Die Fähigkeits-Klassen
teilen sich `Role::Area` (`unsupported`, `supports`, die `probe_*`-Konvention) und
hängen je nach Transport an `Role::Capability` (Redfish) oder `Role::Racadm`. Keine
Klasse kennt beide Transporte; die Redfish-Klassen sind unverändert.

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

**SSH (Phase 2).** Die Fähigkeiten über racadm brauchen nur die Attribute, die die
Redfish-Seite nicht kennt; alles Weitere ist optional:

| Attribut | Bedeutung |
|---|---|
| `ssh` | Standard `1`. `0`: racadm wird nicht benutzt, Phase-2-Methoden sind `Unsupported`. |
| `ssh_username`, `ssh_password` | Standard: `username`, `password`. Nur zusammen. |
| `ssh_port` | Standard 22. Der Port in `host` ist der HTTPS-Port. |
| `ssh_host_key` | Host-Key anpinnen (`ssh-ed25519 AAAA…`). |
| `ssh_known_hosts` | Eine `known_hosts`-Datei. Ohne beides: die des Benutzers. |
| `ssh_verify_host_key` | Standard `1`. `0` nimmt jeden Key; nicht zusammen mit den zwei davor. |
| `ssh_opts` | Weitere `-o Name=Wert` für den SSH-Client, für alte Algorithmen. |
| `racadm` | Ein eigener Transport statt des gebauten. |

Dieselben Zugangsdaten sind der Standard, weil ein iDRAC Web- und SSH-Login aus
derselben Benutzerverwaltung bedient; wer sie trennt, nutzt `ssh_username`/`ssh_password`.
Der Host-Key wird geprüft (Haus-Muster wie bei Rex::LibSSH: Strict an, anpinnen oder
seeden, überschreibbar, nie von selbst aus). `ssh_opts` können die Prüfung nicht
abschwächen. Die Dist setzt keine alten Algorithmen von selbst.

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

## 5. Fähigkeiten

Rückgaben sind Hashrefs oder Arrayrefs von Hashrefs mit festen Schlüsseln in
`snake_case`. Ein Schlüssel, zu dem der Controller nichts liefert, ist vorhanden und
`undef`. `health` ist überall `ok`, `warning`, `critical` oder `undef`.

### 5.1 `capabilities`

`generation` (7, 8, 9, 10), `model`, `firmware`, `redfish_version`, `license`
(`basic`, `express`, `enterprise`, `datacenter` oder `undef`, wenn nicht lesbar).
Die Lizenz kommt seit Phase 2 aus `racadm license view` (Zeilen `License Description`,
bei mehreren die höchste) und wird erst bei `license` oder `facts` gelesen, nie bei
`generation`, `model`, `firmware`, `redfish_version`: Wer nur Redfish nutzt, öffnet
keine SSH-Verbindung. Nicht lesbar heißt: racadm aus, SSH nicht erreichbar oder Login
verweigert, keine Lizenz gelistet.

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

### 5.7 `bios` (Phase 2, racadm)

Attribute heißen `Gruppe.Attribut` wie bei racadm (`BiosBootSettings.BootMode`).

| Methode | Rückgabe / Wirkung |
|---|---|
| `groups` | Arrayref der Gruppennamen. Nur wo der Controller sie listet (iDRAC 8); iDRAC 7 antwortet `Unsupported`. |
| `group($gruppe)` | je Attribut: `name`, `value` (`undef` wenn leer), `read_only` |
| `get('Gruppe.Attribut')` | der Wert; die gestagete Änderung zählt nicht |
| `set('Gruppe.Attribut' => $wert)` | stagt; `name`, `value`, `previous`, `fqdd`, `pending`. Liest vorher: schreibgeschützt ist `Validation`, unbekannt `API` mit `is_not_found`, beides vor dem Schreiben. |
| `commit( reboot => 'none' )` | legt den Job an (`jobqueue create <fqdd> -r <reboot>`); `job_id`, `reboot_job_id`, `fqdd`. `reboot`: `none` (Standard), `graceful`, `forced`, `pwrcycle`. |

Eine Änderung wirkt erst mit Job und Neustart des Servers. Die Dist startet den Server nie
von sich aus neu.

### 5.8 `jobs` (Phase 2, racadm)

| Methode | Rückgabe / Wirkung |
|---|---|
| `list` | je Job: `id`, `name`, `status`, `message`, `message_id`, `percent_complete`, `start_time`, `expiration_time`, `finished` |
| `get($id)` | ein Job, dieselben Schlüssel; unbekannte Jobs sind `API` mit `is_not_found` |
| `delete($id)` | entfernt den Job; ein laufender wird vom Controller verweigert |
| `wait( $id, timeout => 600, interval => 5 )` | fragt `get` ab, bis `finished`; gibt den Job zurück, bei Ablauf der Zeit `undef` |

`id` ist `JID_…` oder `RID_…`, unverändert vom Controller. `finished` heißt: Status
`Completed`, `Completed with Errors`, `Failed`, `Reboot Failed` oder abgebrochen; ob der
Job gelang, steht in `status` und `message`.

### 5.9 `virtual_media` (Phase 2, racadm)

| Methode | Rückgabe / Wirkung |
|---|---|
| `status` | `connected`, `share`, `username`, `attach_mode`, `boot_once`, `enabled` (die letzten drei nur mit Lizenz, sonst `undef`) |
| `connect( location => …, username => …, password => … )` | hängt ein Image ein (`//host/share/a.iso`, `host:/export/a.iso`, `http(s)://…`), gibt den Status zurück; CIFS braucht Benutzer und Passwort |
| `disconnect` | hängt aus, gibt den Status zurück |

Das Passwort wird nie zurückgegeben und steht in keiner Meldung.

### 5.10 Argumente an racadm

racadm meldet Fehler als Text mit Exit-Status 0, und was seine Kommandozeile mit einem
Anführungszeichen, einem Backslash oder Shell-Zeichen macht, ist nicht für jede Firmware
bekannt. Deshalb besteht jedes Argument aus Buchstaben, Ziffern, Leerzeichen und
`_ . : / @ = , + % # -`, sonst `Validation` (ohne den Wert in der Meldung); Wörter mit
Leerzeichen oder `#` kommen in doppelte Anführungszeichen. Folge: ein Passwort mit `"`,
`\`, `$` und ähnlichem kann nicht gesendet werden. Das ist die ehrliche Grenze, kein
Escaping auf Verdacht.

### Nicht in Phase 1 und 2

Storage/RAID, Firmware-Update, Benutzer, Zertifikate, iDRAC-Konfiguration schreiben
(außer BIOS), Async, CLI.

## 6. Fehler

Alle Fehler sind Objekte, stringifizieren zu ihrer Meldung und werden mit `throw`
geworfen, wie in `WWW::Keycloak`.

| Klasse | Wann | Zusätzlich |
|---|---|---|
| `Error::Validation` | falsche Argumente | |
| `Error::Network` | keine HTTP-Antwort, TLS-Fehler; über SSH: Verbindung, Host-Key, Login, Zeitablauf | `cause` (nur SSH: `refused`, `host_key`, `auth`, `timeout`, `other`) |
| `Error::API` | iDRAC antwortet mit Fehler; racadm druckt `ERROR:` | `http_status` (bei racadm `undef`), `message_id` (`RAC1019`, `SWC0242` …), `api_message`, `resolution`; `is_not_found`, `is_unauthorized` |
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
hängt von `WWW-iDRAC` ab und teilt diesen Code, statt ihn zu kopieren. Für racadm gilt
dasselbe: `command_from`, `quote`, `error_from`, `blocks_from` und die `*_from` von Bios,
Jobs, VirtualMedia und Capabilities sind frei von I/O; die I/O liegt allein in
`Racadm::SSH` und ist über das Attribut `runner` austauschbar.

## 8. Tests

- **Unit-Tests** laufen gegen `t/lib/FakeiDRAC.pm`, einen `LWP::UserAgent`-Ersatz, der
  eine Abbildung von Pfad auf Dokument ausliefert: erfundene Dokumente für die
  Unit-Tests, und die Aufnahmen `t/fixtures/idrac7/redfish.json` und
  `t/fixtures/idrac8/redfish.json` für `t/85-fixtures.t`, das jede lesende Methode gegen
  beide Generationen prüft.
- **Fixtures** nimmt `t/idrac/record.pl` auf: nur `GET`, läuft den Redfish-Baum ab und
  ersetzt vor dem Schreiben Service-Tags, Seriennummern, MACs, IPs, Hostnamen, UUIDs und
  Benutzernamen durch feste Platzhalter. Behalten werden nur die Dokumentarten, die die
  Tests lesen, ohne Hersteller-Abschnitte (`Oem`) und ohne den Text von Log-Meldungen.
  Das Repo wird öffentlich; unbereinigte Aufzeichnungen werden nicht committet, und ein
  Mensch liest jede Aufnahme, bevor sie committet wird. Neben jeder Aufnahme liegt ein
  `expect.json`, das sagt, was dieser Controller nicht hat.
- **Live-Suite** `t/90-live-idrac.t` läuft nur mit `IDRAC_HOST`, `IDRAC_USERNAME`,
  `IDRAC_PASSWORD` (dazu `IDRAC_SSL_FINGERPRINT` oder `IDRAC_VERIFY_SSL=0`) und ist
  lesend. Schaltende Tests (Power, `clear_sel`, `manager->restart`) brauchen zusätzlich
  genau `IDRAC_LIVE_DESTRUCTIVE=1`, weil sie eine echte Maschine treffen; den Strom hart
  abzuschalten braucht darüber hinaus `IDRAC_LIVE_FORCE_OFF=1`.

- **racadm.** `t/lib/FakeRacadm.pm` ist der Runner der Unit-Tests: erfundene Werte in den
  Formen, die die Controller am 2026-10-14 druckten, mit etwas Zustand (set, jobqueue
  create/delete, remoteimage), oder eine Aufnahme `t/fixtures/<name>/racadm.json` (Abbildung
  Kommandozeile auf Text; ein nicht aufgenommenes Kommando bricht den Test ab).
  `t/idrac/record-racadm.pl` nimmt auf, nur lesend (`license view`, `get`, `jobqueue view`,
  `remoteimage -s`), bereinigt mit `t/lib/iDRACSanitizeRacadm.pm` und liest die rohe
  Ausgabe, damit Fehlertexte in die Aufnahme kommen. `t/85-fixtures.t` prüft die
  racadm-Methoden gegen beide Aufnahmen; `expect.json` kennt dafür `license`.
  `t/33-racadm-ssh.t` prüft die I/O-Schicht gegen einen Ersatz für Net::OpenSSH.
- **Live, racadm.** `t/92-live-racadm.t`: lesend wie die anderen; Schreibendes (BIOS-Wert
  auf sich selbst setzen, Job anlegen und löschen, Image einhängen) nur mit
  `IDRAC_LIVE_DESTRUCTIVE=1`, Image zusätzlich mit `IDRAC_LIVE_VMEDIA_LOCATION`.

Abhängigkeiten: `Moo`, `Type::Tiny`, `LWP::UserAgent`, `LWP::Protocol::https`,
`IO::Socket::SSL`, `HTTP::Message`, `JSON::MaybeXS`, `namespace::autoclean`, `Net::OpenSSH`
(geladen erst, wenn racadm benutzt wird) mit `IO::Pty` für die Passwort-Abfrage; für die
Tests zusätzlich `URI`; Perl 5.020. Zur Laufzeit außerdem das Programm `ssh` von OpenSSH.

## 9. Am Gerät zu klären (Karte 1)

Diese Punkte sind keine Lücken im Design, sondern Messungen, die das Design an den
genannten Stellen festlegen. Karte 1 beobachtet beide iDRACs lesend, nimmt die Fixtures
auf und trägt die Ergebnisse hier ein.

| Frage | Folge |
|---|---|
| Firmware-Stand beider Controller; ist Redfish überhaupt vorhanden? | Zu alte Firmware: Update ist Voraussetzung und Handarbeit, keine Aufgabe der Dist. |
| Welche TLS-Versionen und Cipher spricht der Controller? | Geht nur TLS 1.0/1.1: wie oben, Firmware-Update; die Dist bekommt keinen unsicheren Standard. |
| Ist die Lizenzstufe über Redfish lesbar? | Wenn nein, bleibt `license` in Phase 1 `undef` und wird in Phase 2 nachgeliefert. Nein (siehe unten); Phase 2 liefert sie über racadm. |
| Wie viele Sessions lässt der Controller zu, wie lange leben sie? | Bestätigt oder ändert den Standard `session => 1`. |
| Wo liegen SEL und Lifecycle-Log, kommen Einträge inline oder einzeln? | Legt die Umsetzung von `logs` und `limit` fest. |
| Welche Schlüssel aus Abschnitt 5 liefert iDRAC 7/8 tatsächlich? | Schlüssel ohne Quelle bleiben `undef`; fehlende ganze Ressourcen werden `Unsupported`. |
| WS-Man oder racadm über SSH als zweiter Transport? | **Entschieden am 2026-10-14: racadm über SSH.** Messung und Begründung unten. |

### Gemessen am 2026-10-05

Beide Geräte wurden rein lesend aufgenommen (`t/idrac/record.pl`), danach lief
`t/90-live-idrac.t` lesend gegen beide durch. Geschaltet wurde nichts: Beide sind
Produktivmaschinen.

| Frage | PowerEdge R720xd (iDRAC 7) | PowerEdge T330 (iDRAC 8) |
|---|---|---|
| Firmware, Redfish | 2.65.65.65, Redfish 1.4.0 | 2.50.50.50, Redfish 1.0.2 |
| Modell des Managers | `12G Monolithic`, als iDRAC 7 erkannt | `13G Monolithic`, als iDRAC 8 erkannt |
| TLS | TLS 1.2, ECDHE-RSA-AES256-GCM-SHA384 | TLS 1.2, DHE-RSA-AES256-GCM-SHA384 |
| Service-Root | 200 mit und ohne Schrägstrich, kein Redirect | ebenso |
| Lizenz über Redfish | kein Lizenz-Dokument im Baum | ebenso |
| Sessions | `/redfish/v1/Sessions`, Timeout 1800 s | ebenso |
| Logs | Dienste `SEL` und `LC` unter `LogServices/Sel` und `/Lclog`; Einträge inline, neueste zuerst | ebenso; der Schlüssel heißt hier `MessageID` |
| Reset-Typen | `On ForceOff ForceRestart GracefulShutdown PushPowerButton Nmi` | `On ForceOff GracefulRestart PushPowerButton Nmi` |
| Memory-Collection | vorhanden | fehlt |
| Abgelaufen / behalten | 193 Dokumente in 98 s / 66 | 56 in 38 s / 40 |
| Nicht erreichbar | `Storage/RAID.Integrated.1-1` (404) | `VirtualMedia` (403) |

Was daraus folgt:

- **Das Werkszertifikat** lässt sich mit `ssl_fingerprint` anpinnen; so liefen Aufnahme und
  Live-Suite. Die Dist braucht keinen abgesenkten TLS-Standard.
- **`license` blieb in Phase 1 `undef`**; Phase 2 liest sie über racadm (unten).
- **Session-Login und -Logout funktionieren**; nach den Läufen war auf beiden keine Session
  offen. Wie viele Sessions ein Controller zulässt, wurde an den Produktivgeräten nicht
  ausgereizt. Keep-Alive hat über 193 Anfragen gehalten.
- **Schlüssel, die diese Controller nicht liefern,** stehen je Gerät in
  `t/fixtures/<name>/expect.json`: `fqdn` des iDRAC (leer), `asset_tag` (nicht gesetzt),
  `link_up` (kein `LinkStatus`), auf dem R720xd dazu `hostname`, `health` der
  Netzwerkschnittstellen und `output_watts` der Netzteile.
- **Drei Annahmen des Codes waren falsch** und sind korrigiert: der Name des
  Lifecycle-Log-Dienstes (`LC`), die Schreibung `MessageID`, und die Netzteil-Leistung,
  die der iDRAC 7 nur unter `InputRanges` nennt.
- **Schalten:** `power->cycle` bietet keines der beiden an. Sanftes `off` fehlt auf dem
  T330, sanftes `restart` auf dem R720xd. **Offen für Getty:** ob `off` und `restart` dort
  ersatzweise `PushPowerButton` bzw. die harte Form senden sollen, oder ob `Unsupported`
  die richtige Antwort bleibt.
- **Zweiter Transport:** `VirtualMedia` antwortet auf dem T330 mit 403, was auf die
  Lizenzstufe deutet. Bestätigt am 2026-10-14: der T330 hat eine Express-Lizenz, und
  racadm nennt für Virtual Media `SWC0242`. Die Entscheidung WS-Man oder racadm: unten.

### Vermutungen aus dem Review (2026-10-05)

Stand nach der Messung: Die Reset-Typen stimmen für den T330 und nicht für den R720xd.
`LinkStatus` fehlt auf beiden, die Memory-Collection auf dem T330. `Thermal` und `Power`
liefern die Messwerte direkt, der Service-Root antwortet ohne Redirect. Die Zeilen zu 409
und 503 sind ungeprüft, weil nichts geschaltet wurde.

**Schaltender Lauf am 2026-10-06 gegen den R720xd (iDRAC 7, 2.65), mit Gettys Freigabe.**
`clear_sel`, sanftes `off`, `on` und `manager->restart` sind durchgelaufen. Gemessen:

- Nach `clear_sel` beantwortet der iDRAC 7 jedes Lesen des Event-Logs etwa eine Minute
  lang mit 500 („Failed to get SEL count“), solange er löscht; IPMI meldet in der Zeit
  0x81. Die Live-Suite wartet das jetzt ab.
- Sanftes `off` war nach rund 35 Sekunden erreicht, `on` sofort; der Controller war nach
  seinem Neustart nach etwa drei Minuten wieder da.
- Eine Anmeldung, die der hochfahrende Controller noch annimmt, deren Antwort aber nicht
  mehr ankommt, bleibt als offene Sitzung auf dem Gerät, bis sie abläuft.
- Der Server kam danach nicht von selbst hoch: Mit nur einem versorgten Netzteil hält das
  BIOS beim Kaltstart mit „Power required exceeds PSU wattage … F1 to continue“ an
  (`ErrPrompt=Enabled`). Das ist Sache der Maschine, nicht der Bibliothek, gehört aber vor
  jeden schaltenden Lauf geprüft.

Nicht gelaufen: die harten Formen (`off( force => 1 )`, `restart( force => 1 )`) und alles
Schaltende auf dem iDRAC 8.

Der Review des gebauten Stands hat aus Dells Dokumentation Vermutungen über iDRAC 7/8 mit
Firmware 2.x genannt. Sie sind nicht gemessen und nicht umgesetzt; Karte 1 prüft sie an
den Aufnahmen.

| Vermutung | Wenn sie stimmt |
|---|---|
| Angebotene Reset-Typen sind nur `On`, `ForceOff`, `GracefulRestart`, `PushPowerButton`, `Nmi` | `power->off`, `restart( force => 1 )` und `cycle` sind auf beiden Geräten `Unsupported`. Getty entscheidet, ob `off` dann `PushPowerButton` senden soll, wenn der Server an ist. |
| `on` oder hartes `off` in einem Zustand, der schon erreicht ist, wird mit 409 beantwortet | Die schaltenden Methoden sollten zurückkehren, ohne zu senden, wenn der Zustand schon stimmt. |
| `LinkStatus` fehlt an den Netzwerkschnittstellen | `link_up` ist immer `undef`; gehört dann ins `expect.json`. |
| Die `Memory`-Collection fehlt auf früher 2.x-Firmware | `system->memory` ist `Unsupported`; das ist schon behandelt. |
| `Thermal` und `Power` enthalten auf früher 2.x-Firmware nur Verweise statt der Messwerte | Die Sensoren kämen als Zeilen mit lauter `undef` zurück; das `expect.json` zeigt es. |
| Während der iDRAC neu startet, antwortet er auch mit 503 | Anfragen in der Zeit enden dann in `Error::API`, nicht nur in `Error::Network`; das POD von `manager->restart` wäre zu ergänzen. |
| Der Service-Root `/redfish/v1/` antwortet mit einem Redirect | Der Client folgt keinem Redirect; der Pfad des Service-Root wäre dann anzupassen. |

### Phase 2: zweiter Transport, gemessen am 2026-10-14

Beide Controller wurden rein lesend per SSH befragt (nichts gesetzt, angelegt, gelöscht,
eingehängt; kein Power geschaltet). Zugang: Benutzer und Passwort wie für Redfish, ein
`ssh` von OpenSSH 10 mit seinen Standard-Algorithmen, Host-Key geprüft gegen einen mit
`ssh-keyscan` geholten Key (Strict an). **Es waren keine alten Algorithmen nötig.** Die
Controller bieten `publickey` und `keyboard-interactive`, kein `password`: ein Client, der
nur `password` versucht, scheitert mit `Permission denied`; Net::OpenSSH beantwortet die
Passwort-Abfrage des `keyboard-interactive` über sein Terminal. Der Exit-Status von
`ssh ... racadm ...` ist immer 0, auch bei einem Fehler: Fehler stehen nur im Text.

| Frage | PowerEdge R720xd (iDRAC 7, FW 2.65) | PowerEdge T330 (iDRAC 8, FW 2.50) |
|---|---|---|
| SSH Port 22, `racadm getversion` | ja | ja |
| `racadm license view` | Baum mit Tabs; `License Description = iDRAC7 Enterprise License` | `... iDRAC8 Express License` |
| `racadm get BIOS` (Gruppenliste) | `ERROR: Unable to perform requested operation.` | 13 Gruppennamen, einer je Zeile |
| `racadm get BIOS.<Gruppe>` | ja, `[Key=BIOS.Setup.1-1#<Gruppe>]`, `#Name=Wert` schreibgeschützt | ebenso |
| `racadm get BIOS.<Gruppe>.<Attr>` | ja, ein Eintrag | ebenso |
| Unbekannte Gruppe / Attribut | `ERROR: RAC1020` / `ERROR: RAC1019` | ebenso |
| `racadm jobqueue view` | Kopfzeile, dann `[Job ID=JID_…]`-Blöcke mit `Key=Value`; ein abgeschlossener Job | nur die Kopfzeile (leere Queue) |
| `racadm jobqueue view -i <id>` | ein Block unter `---- JOB ----` | unbekannte Id: `RAC992: Invalid job` ohne `ERROR:` |
| `racadm remoteimage -s` | `Remote File Share is Disabled` + `UserName`/`Password`/`ShareName` | ebenso |
| `racadm get iDRAC.VirtualMedia` | `Attached`, `BootOnce`, `Enable`, ... | `ERROR: SWC0242 : A required license is missing or expired.` + `Required License -- Virtual Media` |
| `racadm help remoteimage` / `jobqueue` / `set` | Verwendung und Optionen (`-c -u -p -l`, `-d`, `-s`; `jobqueue create <fqdd> -r none\|pwrcycle\|graceful\|forced`, `delete -i`) | ebenso |

**Entscheidung: racadm über SSH.**

- **Strukturierte Daten ohne XML.** Die Ausgabe ist Key=Value in `[Key=...]`- und
  `[Job ID=...]`-Blöcken mit festen Namen; ein Parser ist eine Handvoll reiner Funktionen.
  WS-Man hieße SOAP/XML-Hüllen, Namensräume und Enumerationskontexte, auf dem R720xd und
  dem T330 gegen zwei Firmware-Stände zu verifizieren, und die Dist hätte `DMTF-WSMan`
  (2012, verwaist) als einzige Orientierung.
- **Deckt alles ab, was Phase 2 will.** BIOS lesen und setzen (`get`/`set`), Job-Queue
  (`jobqueue view/create/delete`), Virtual Media (`remoteimage`), Lizenz (`license view`)
  gingen auf beiden Geräten oder meldeten die Lizenz als Grund.
- **Dieselben Zugangsdaten**, kein weiterer Port, keine weitere TLS-Konfiguration.
- **Kosten:** Die Antworten sind langsam (Sekunden je Kommando; ein Lauf der lesenden
  Live-Suite 60 bis 100 s), SSH ist ein zweiter Dienst, der am iDRAC angeschaltet sein
  muss und nur wenige Sessions zulässt, und Fehler sind Text, nicht Status. Das
  Letzte fängt `Racadm::error_from`, das Zweite beendet die Verbindung in `DEMOLISH`.

**SSH-Bibliothek: Net::OpenSSH.** Installiert, reines Perl, und es steuert das `ssh` der
Maschine: Algorithmen, Host-Key-Prüfung (`known_hosts`, `StrictHostKeyChecking`) und
`ssh_config` sind die des gepflegten OpenSSH, nicht eine Nachbildung. Es beantwortet die
Passwort-Abfrage über ein Terminal (`IO::Pty`), also nie auf einer Kommandozeile.
`Net::SSH2` (libssh2) ist hier nicht installiert und braucht eine C-Bibliothek,
`Rex::LibSSH` ist auf Rex zugeschnitten. Nachteil: ein `ssh`-Programm ist Laufzeit-Voraussetzung.

**Host-Key.** Strict an. `ssh_host_key` pinnt einen Key (die Dist schreibt eine temporäre
`known_hosts` nur mit ihm), `ssh_known_hosts` nennt eine Datei, sonst gilt die des
Benutzers; `ssh_verify_host_key => 0` ist die ausdrückliche Entscheidung des Aufrufers
und nicht zusammen mit den beiden anderen erlaubt. Ein Login-Versuch je Verbindung
(`NumberOfPasswordPrompts=1`), damit ein falsches Passwort den Controller nicht mehrfach
anläuft.

**Nicht gemessen** (nicht gelaufen, nur aus `racadm help` der beiden Controller und
den Antwortformen abgeleitet): `racadm set BIOS...`, `jobqueue create`, `jobqueue delete`,
`remoteimage -c`/`-d`, die Form von `remoteimage -s` mit eingehängtem Image, die Antwort
auf `set` und `jobqueue create` (die Dist sucht darin `pending`, `JID_…`, `RID_…`), Jobs
im Zustand `Running`/`Scheduled`, mehrere Lizenzen, und alles Schreibende auf dem
iDRAC 8. `racadm get BIOS` auf dem iDRAC 7 (kein Gruppenverzeichnis) ist gemessen und
`bios.groups` dort `Unsupported`. Wie der racadm-Parser der Controller Anführungszeichen
und Backslashes behandelt, ist nicht gemessen; deshalb lässt die Dist solche Zeichen in
Argumenten nicht zu (Abschnitt 5.10).

## 10. Phasen

1. **Anlage.** Dist-Gerüst, Agenten-Team und Board (Abschnitt 11), noch ohne Code.
2. **Karte 1 – beobachten.** Beide iDRACs lesend abfragen, Fixtures aufnehmen, Abschnitt 9
   beantworten, Spec nachschärfen. Der Recorder braucht den Transport; deshalb entstehen
   Fehlerklassen, HTTP-Rolle und Redfish-Transport hier, vor dem Beobachten.
3. **Phase 1 – bauen.** Fassade, `capabilities` und die fünf Fähigkeits-Klassen aus
   Abschnitt 5, Unit-Tests, Fixture-Test über beide Aufnahmen, Live-Suite.
4. **Phase 2 – Lücken auf iDRAC 7/8. Gebaut am 2026-10-14.** Zweiter Transport (racadm
   über SSH, Abschnitt 9), Transport-Abstraktion (`Role::Transport`, `Role::Area`),
   `Racadm`/`Racadm::SSH`, die Fähigkeiten `bios`, `jobs`, `virtual_media` und die
   Lizenz in `capabilities`, Unit-Tests gegen `FakeRacadm`, Aufnahmen
   `racadm.json` je Generation, lesende Live-Suite `t/92-live-racadm.t`. Gegen beide
   Geräte lesend gelaufen; Schreibendes (`set`, `commit`, `jobs->delete`,
   `virtual_media->connect`/`disconnect`) ist in der Live-Suite hinter
   `IDRAC_LIVE_DESTRUCTIVE=1` und gegen kein Gerät gelaufen.
5. **`Net::Async::iDRAC`.**
6. **Phase 3 – iDRAC 9/10.** Dell-OEM-Actions, Storage, Firmware-Update; erst mit einem
   solchen Gerät im Zugriff.
