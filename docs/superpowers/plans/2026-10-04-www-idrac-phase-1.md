# WWW::iDRAC Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Die Dist `WWW-iDRAC` anlegen, beide vorhandenen iDRACs (7 und 8) lesend aufnehmen und Phase 1 bauen: Fassade, Fehler, Redfish-Transport, `capabilities` und die fünf Fähigkeits-Klassen `system`, `power`, `sensors`, `logs`, `manager`, mit Unit-Tests, Fixture-Test und Live-Suite.

**Architecture:** Moo-Klassen nach dem Muster von `WWW::Keycloak`. `WWW::iDRAC` ist die Fassade und baut einen Redfish-Transport (`WWW::iDRAC::Redfish`: Session, einmaliges Neu-Anmelden bei 401, Navigation ohne feste Namen) und darauf fünf Fähigkeits-Klassen. Diese geben normalisierte Hashes mit festen Schlüsseln zurück, nie Redfish-Dokumente; die Übersetzung liegt in reinen Funktionen (`*_from`) ohne I/O, damit ein Async-Zwilling sie mitbenutzt. Was ein Controller nicht hat, wird vor dem Senden zu `WWW::iDRAC::Error::Unsupported`.

**Tech Stack:** Perl 5.20+, Moo, Types::Standard, LWP::UserAgent, LWP::Protocol::https, IO::Socket::SSL, HTTP::Message, JSON::MaybeXS. Dist::Zilla mit `[@Author::GETTY]`.

**Spec:** `docs/superpowers/specs/2026-10-04-www-idrac-design.md` (freigegeben 2026-10-04). Bis Aufgabe 1 liegt sie im Hub `~/dev/perl-developer`, danach in der Dist.

## Ausgeführt am 2026-10-05

Aufgaben 1 bis 4 und 6 bis 11 sind vollständig umgesetzt, ein Commit pro Aufgabe (`56a8192` bis `e50bbd2`); von Aufgabe 12 der Test, von Aufgabe 13 Live-Suite und Dokumentation (`a7b1576`, `7af422f`). **Offen sind Aufgabe 5, Step 3 von Aufgabe 12 und Step 3 und 4 von Aufgabe 13**: Sie brauchen die beiden Geräte.

Danach hat ein unabhängiger Review des ganzen Stands einen kritischen und sieben wichtige Befunde gebracht, die in fünf eigenen Commits behoben sind (`05b3ff5` bis `cf275b3`). **Der Code im Repo weicht dort von den Listings unten ab; maßgeblich ist das Repo.** Was sich geändert hat:

- **Sessions.** Offene Sessions werden in einem `END`-Block beendet, weil ein Client in einer dateiweiten Variable bis in die globale Zerstörung lebt und das Logout dort scheiterte. Ein 401, der nicht an der Session liegt, hinterlässt keine Session mehr pro Anfrage. Ein `logout`, das der Controller ablehnt, wirft nicht.
- **Transport.** Eine Erfolgsantwort, deren Body kein JSON ist, ist ein `Error::API`. `locate` merkt sich keinen Fehltreffer. Der User-Agent folgt keinem Redirect (`max_redirect => 0`), weil der Token oder das Passwort mitginge. Folge für Aufgabe 5: Antwortet ein iDRAC auf `/redfish/v1/` mit einem Redirect, zeigt sich das dort als `Error::API` mit Status 30x.
- **`supports`.** Die Proben holen das Dokument hinter dem Link, nicht nur den Link; `supports` und Methode sagen jetzt dasselbe. Ein 404 auf dem Weg zu System, Chassis oder Manager und eine Antwort, die kein Dokument ist, werden `Unsupported`.
- **Aufnahmen.** Der Recorder behält nur noch die Dokumentarten, die die Tests lesen (nach `@odata.type`); alles andere wird für die Zusammenfassung abgelaufen und verworfen. Die Bereinigung lässt `Oem`, `Location` und den Text von Log-Meldungen weg, erkennt Schlüssel an ihrem letzten Punkt-Bestandteil (`Users.3.UserName`), findet benannte Werte unabhängig von der Schreibung, lässt Zahlen Zahlen sein und meldet Lecks als Art und Dokument statt die Werte auszugeben.
- **Fixture-Test.** Jede Aufnahme braucht ein `expect.json` daneben, das sagt, was der Controller nicht hat; ohne die Datei scheitert der Test und druckt, was er gefunden hat (siehe Aufgabe 12).
- **Live-Suite.** Der schaltende Teil verlangt genau `IDRAC_LIVE_DESTRUCTIVE=1`, schaltet den Strom nur mit `IDRAC_LIVE_FORCE_OFF=1` hart ab und stellt den vorgefundenen Zustand wieder her.

Nicht umgesetzt, sondern für Aufgabe 5 vorgemerkt: die Vermutungen des Reviews über das Verhalten von iDRAC 7/8 (Spec-Abschnitt 9, zweite Tabelle).

## Stand des Codes in diesem Plan

Der gesamte Code dieses Plans ist am 2026-10-04 als Wegwerf-Prototyp gelaufen, Aufgabe für Aufgabe in der Reihenfolge unten aufgebaut: `prove -lr t` war nach jeder Stufe grün, am Ende 16 Dateien und 92 Tests. Zusätzlich geprüft:

- `t/idrac/record.pl` von Anfang bis Ende gegen den nachgebauten iDRAC, die Aufnahme danach in `t/85-fixtures.t`.
- `t/90-live-idrac.t` einschließlich des schaltenden Teils gegen den nachgebauten iDRAC.
- Die TLS-Optionen gegen einen echten lokalen TLS-Server mit selbstsigniertem Zertifikat auf fremden Namen: Standard lehnt ab, `ssl_fingerprint` nimmt an, ein falscher Fingerprint lehnt ab, `ssl_ca_file` allein scheitert am Namen, `verify_ssl => 0` nimmt an.
- Das Session-Ende beim Programmende, auch nach `exit` und `die`, ohne den Exit-Code zu verändern.

**Nicht geprüft:** nichts davon ist gegen einen echten iDRAC gelaufen, und `dzil test` ist nicht gelaufen. Alles, was der Code über Redfish-Feldnamen eines iDRAC 7/8 annimmt, ist bis Aufgabe 5 eine Annahme. Dafür gibt es die Aufgaben 5, 12 und 13.

## Abweichungen von der Spec

Beim Bau des Prototyps entschieden, in der Spec nachgetragen:

- **Reihenfolge.** Der Recorder braucht den Transport. Deshalb stehen Fehler, HTTP-Rolle und Transport (Aufgaben 2 bis 4) vor dem Beobachten am Gerät (Aufgabe 5) und gehören mit zu Karte 1.
- **`URI` ist nur Test-Abhängigkeit**, der Code unter `lib/` benutzt es nicht.
- **`power->state`** kann neben `on` und `off` einen Zwischenzustand liefern (`powering_on`), in derselben Form.
- **`ssl_ca_file` allein passt nicht zum Werkszertifikat**, weil dessen Name nicht die Adresse ist. Der Weg für das Werkszertifikat ist `ssl_fingerprint`.

Ohne Änderung der Spec, aber gut zu wissen:

- Die Session beendet der Transport (`WWW::iDRAC::Redfish::DEMOLISH`), nicht die Fassade. So endet sie auch, wenn ein Teil die Fassade überlebt.
- `capabilities->model` ist das Modell des Servers. Das Modell, das der Manager meldet (`13G Monolithic`), steht in `manager->info`.
- `capabilities->license` ist in Phase 1 immer `undef`. Ob die Lizenz lesbar ist, misst Aufgabe 5; wenn ja, entsteht eine Karte.
- `logs` holt ohne Angabe 50 Einträge und nimmt an, dass der Controller die neuesten zuerst liefert. Die Live-Suite prüft das.
- Über die Spec hinaus gibt es `WWW::iDRAC::Util`, `WWW::iDRAC::Role::Capability`, `supports` auch an jeder Fähigkeits-Klasse und `t/lib/iDRACRecorder.pm`.

## Ausführung

- **Aufgabe 1** läuft in der Hub-Session (`~/dev/perl-developer`); dort gibt es die Agenten der Dist noch nicht.
- **Aufgaben 2 bis 13** laufen in `~/dev/p5-www-idrac` mit den Agenten der Dist. Der Worker baut, der Release-Manager committet.
- **Aufgabe 5** braucht Getty: Adressen und Zugangsdaten der beiden iDRACs, und die Durchsicht der Aufnahmen. Ist der Zugriff noch nicht da, gehen die Aufgaben 6 bis 11 trotzdem; sie hängen nicht an den Aufnahmen. Aufgabe 12 und der Live-Lauf in Aufgabe 13 warten auf Aufgabe 5.
- Kein GitHub-Repo, kein Push. Beides entsteht erst auf Gettys Zuruf.

## Global Constraints

- Perl 5.020. Laufzeit-Abhängigkeiten genau die im `cpanfile` aus Aufgabe 1.
- Ein Paket pro Datei, jede Datei unter `lib/` mit `# ABSTRACT:` und `our $VERSION = '0.001';`. Kein `require` zum verzögerten Laden unter `lib/`.
- Jeder Fehler ist ein Objekt aus `WWW::iDRAC::Error::*`, geworfen mit `->throw`. Das Passwort steht in keiner Fehlermeldung und in keinem Fixture.
- Fähigkeits-Klassen geben Hashrefs oder Arrayrefs von Hashrefs mit festen Schlüsseln in `snake_case` zurück, nie Redfish-Dokumente. Ein Schlüssel ohne Quelle ist vorhanden und `undef`. `health` ist `ok`, `warning`, `critical` oder `undef`. Die Schlüssel stehen einmal, in `t/lib/iDRACShapes.pm`, und sind die aus Spec-Abschnitt 5.
- Nur `WWW::iDRAC::Redfish` kennt Pfade. Im Code unter `lib/` steht kein fester Ressourcenname wie `System.Embedded.1` oder `iDRAC.Embedded.1` (POD-Beispiele ausgenommen).
- `WWW::iDRAC::Error::Unsupported` werfen nur die Fähigkeits-Klassen, und zwar bevor etwas gesendet wird. Der Transport übersetzt nichts.
- Jede öffentliche Methode `x` einer Fähigkeits-Klasse hat ein `probe_x`.
- TLS-Prüfung ist standardmäßig an. Die Dist schaltet weder TLS-Versionen noch Cipher herunter.
- Keine Transport-Abstraktion in Phase 1.
- Controller-Verhalten wird nicht aus dem Gedächtnis kodiert. Die Standard-Dokumente von `t/lib/FakeiDRAC.pm` sind erfunden und sagen das; was ein echter iDRAC antwortet, steht in `t/fixtures/<name>/redfish.json`.
- Fixtures laufen durch `iDRACSanitize` und werden von einem Menschen gelesen, bevor sie committet werden.
- Jede `.t`-Datei beginnt mit `#!/usr/bin/env perl`, `use strict; use warnings; use Test::More;` und endet mit `done_testing;`. Tests laufen mit `prove -lr t`.
- Die Live-Suite läuft nur mit `IDRAC_HOST`, `IDRAC_USERNAME`, `IDRAC_PASSWORD`. `IDRAC_LIVE_DESTRUCTIVE=1` setzt nie ein Agent, nur Getty.
- **Ab Aufgabe 2 committet niemand außer `www-idrac-release-manager`.** Jede Aufgabe endet mit einem commit-fertigen Baum und einer Übergabe.

## Review Focus

1. **Eine Session, die niemand beendet.** Ein iDRAC lässt nur wenige zu; ein Skript, das stirbt oder `logout` vergisst, sperrt nach ein paar Läufen alle aus. Erwartet: Die Session endet mit dem letzten Objekt, das sie benutzt, und ein Logout, das der Controller ablehnt, wirft nicht. Tests `a session is ended when the object goes away` in `t/30-redfish.t` (Aufgabe 3), `no session is left behind` in `t/40-facade.t` (Aufgabe 6), `the capabilities outlive the facade` in `t/60-capabilities.t` (Aufgabe 11).
2. **Der Controller startet mitten im Lauf neu oder die Session läuft ab.** Erwartet: genau ein neuer Login, dann geht es weiter; bei falschem Passwort ein klarer 401 ohne Schleife und ohne Passwort in der Meldung. Tests `a refused token is renewed once` und `wrong credentials` in `t/30-redfish.t` (Aufgabe 3), `restart` in `t/54-manager.t` (Aufgabe 10).
3. **Ein Controller, dem eine Ressource fehlt** (keine Memory-Collection, kein Thermal, keine Log-Services, ein Link ins Leere). Erwartet: `Unsupported` mit dem Namen der Fähigkeit, kein roher 404 und kein Absturz; `supports` sagt dasselbe. Tests `memory` und `supports` in `t/50-system.t` (Aufgabe 6), `a chassis without sensors` in `t/52-sensors.t` (Aufgabe 8), `a controller without these logs` in `t/53-logs.t` (Aufgabe 9), und `t/85-fixtures.t` gegen die echten Aufnahmen (Aufgabe 12).
4. **Messwerte, die fehlen oder keine Zahl sind** (leerer Sockel, `null`, `"N/A"`, eine Liste, die keine ist). Erwartet: Schlüssel vorhanden und `undef`, eine leere Liste statt eines Absturzes, keine Warnung. Tests `t/15-util.t` (Aufgabe 6), `documents that are not what they should be` in `t/52-sensors.t` (Aufgabe 8), und die Zeile `no warnings` am Ende jeder Test-Datei der Fähigkeits-Klassen.
5. **Ein Schaltbefehl, den dieser Controller nicht anbietet** (`PowerCycle` fehlt in den erlaubten Werten). Erwartet: `Unsupported`, und es wurde nichts gesendet. Tests `an order this controller does not offer` in `t/51-power.t` (Aufgabe 7), `a controller that offers less` in `t/54-manager.t` (Aufgabe 10), `clear_sel` ohne Action in `t/53-logs.t` (Aufgabe 9).

## Dateien

| Datei | Verantwortung | Aufgabe |
|---|---|---|
| `dist.ini`, `cpanfile`, `Changes`, `README.md`, `CLAUDE.md`, `.gitignore`, `LICENSE`, `.github/workflows/ci.yml`, `.claude/**` | Gerüst, Agenten-Team | 1 |
| `lib/WWW/iDRAC/Error.pm`, `Error/Validation.pm`, `Error/Network.pm`, `Error/API.pm`, `Error/Unsupported.pm` | Fehlerhierarchie | 2 |
| `lib/WWW/iDRAC/Role/HTTP.pm` | Senden, JSON, Redfishs Fehlerdokument | 2 |
| `lib/WWW/iDRAC/Redfish.pm` | Transport: Session, Verben, `members`, `locate` | 3 |
| `t/lib/FakeiDRAC.pm` | nachgebauter iDRAC für die Unit-Tests | 3 |
| `t/lib/iDRACSanitize.pm` | Aufnahmen bereinigen | 4 |
| `t/lib/iDRACRecorder.pm`, `t/idrac/record.pl` | Redfish-Baum aufnehmen | 4 |
| `t/fixtures/idrac7/redfish.json`, `t/fixtures/idrac8/redfish.json` | was die echten Controller antworten | 5 |
| `lib/WWW/iDRAC/Util.pm` | reine Übersetzungen | 6 |
| `lib/WWW/iDRAC/Role/Capability.pm` | was die Fähigkeits-Klassen teilen | 6 |
| `lib/WWW/iDRAC/System.pm` | Inventar | 6 |
| `lib/WWW/iDRAC.pm` | Fassade (der Stub wird ersetzt, danach je Aufgabe ergänzt) | 6 bis 11 |
| `t/lib/iDRACShapes.pm` | die dokumentierten Schlüssel, einmal | 6 |
| `lib/WWW/iDRAC/Power.pm` | Schalten, Leistungsaufnahme | 7 |
| `lib/WWW/iDRAC/Sensors.pm` | Temperaturen, Lüfter, Spannungen, Netzteile | 8 |
| `lib/WWW/iDRAC/Logs.pm` | SEL und Lifecycle-Log | 9 |
| `lib/WWW/iDRAC/Manager.pm` | der iDRAC selbst | 10 |
| `lib/WWW/iDRAC/Capabilities.pm` | Fakten und `supports` | 11 |
| `t/85-fixtures.t` | jede lesende Methode gegen jede Aufnahme | 12 |
| `t/90-live-idrac.t`, `README.md`, `CLAUDE.md`, `Changes` | Live-Suite, Einstieg | 13 |

Reihenfolge: 1 → 2 → 3 → 4 → 5, dann 6 → 7 → 8 → 9 → 10 → 11 → 12 → 13. Zuordnung zum Board: Aufgaben 2 bis 5 → Karte 1 (beobachten), Aufgaben 6 bis 13 → Karte 2 (Phase 1).

---

### Task 1: Anlage — Repo, Gerüst, Agenten-Team, Board

Läuft in der Hub-Session. Vorbild ist das Gerüst von `p5-www-authentik` (dort Commit `3c9b5ac`).

**Files:**
- Create: `~/dev/p5-www-idrac/` mit `dist.ini`, `cpanfile`, `Changes`, `README.md`, `CLAUDE.md`, `.gitignore`, `LICENSE`, `.github/workflows/ci.yml`, `lib/WWW/iDRAC.pm`, `t/00-load.t`
- Create: `~/dev/p5-www-idrac/.claude/` mit `agents/www-idrac-{worker,test-writer,release-manager,doc-writer}.md`, `rules/www-idrac-rules.md`, `skills/www-idrac-core/SKILL.md`, `settings.json`, `skilletor.json`, `.gitignore`
- Create: `~/dev/p5-www-idrac/docs/superpowers/specs/2026-10-04-www-idrac-design.md`, `docs/superpowers/plans/2026-10-04-www-idrac-phase-1.md` (aus dem Hub)
- Delete (Hub): `docs/superpowers/specs/2026-10-04-www-idrac-design.md`, `docs/superpowers/plans/2026-10-04-www-idrac-phase-1.md`

**Interfaces:**
- Produces: ein Repo, in dem `prove -lr t` und `dzil test` grün sind, die vier Agenten `www-idrac-*` starten und das Board fünf Karten hat.

- [ ] **Step 1: Repo und Dist-Gerüst**

```bash
mkdir ~/dev/p5-www-idrac && cd ~/dev/p5-www-idrac && git init -b main
mkdir -p lib/WWW t .github/workflows docs/superpowers/specs docs/superpowers/plans
```

`dist.ini` (ohne `irc`-Zeile: für diese Dist gibt es keinen Kanal, und erfunden wird keiner):

```ini
name    = WWW-iDRAC
author  = Torsten Raudssus <getty@cpan.org>
license = Perl_5
copyright_holder = Torsten Raudssus <torsten@raudssus.de> L<https://raudssus.de/>
copyright_year   = 2026

[@Author::GETTY]
```

`cpanfile`:

```perl
requires 'perl', '5.020';
requires 'HTTP::Message';
requires 'IO::Socket::SSL';
requires 'JSON::MaybeXS';
requires 'LWP::Protocol::https';
requires 'LWP::UserAgent';
requires 'Moo';
requires 'Type::Tiny';
requires 'namespace::autoclean', '0.16';

on test => sub {
    requires 'Test::More', '0.96';
    requires 'URI';
};
```

`Changes`:

```
Revision history for WWW-iDRAC

{{$NEXT}}
    - Distribution skeleton
```

`lib/WWW/iDRAC.pm`:

```perl
package WWW::iDRAC;

# ABSTRACT: Perl client for Dell iDRAC - inventory, power, sensors and logs over Redfish

use strict;
use warnings;

our $VERSION = '0.001';

1;

__END__

=head1 DESCRIPTION

This is a skeleton. Nothing is implemented yet; the planned shape is described
in F<docs/superpowers/specs/2026-10-04-www-idrac-design.md> and tracked on the
karr board.

=cut
```

`t/00-load.t`:

```perl
#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

for (qw(
  WWW::iDRAC
)) {
  use_ok($_);
}

done_testing;
```

`README.md`:

```markdown
# WWW-iDRAC

Perl client for the management controller of Dell PowerEdge servers (iDRAC): inventory,
power, sensors and logs, over Redfish.

**Status: skeleton.** Nothing is implemented yet.

## License

This library is free software; you can redistribute it and/or modify it under the same
terms as Perl itself.
```

`.gitignore` und `.github/workflows/ci.yml` aus dem Geschwister-Repo, mit dem Namen der Dist; die authentik-eigenen Zeilen (`.env`, der `live`-Job) entfallen:

```bash
git -C ~/dev/p5-www-authentik show 3c9b5ac:.gitignore | sed 's/WWW-Authentik/WWW-iDRAC/' > .gitignore
git -C ~/dev/p5-www-authentik show 3c9b5ac:.github/workflows/ci.yml > .github/workflows/ci.yml
grep -n -i authentik .gitignore .github/workflows/ci.yml
```

Expected: `grep` findet nichts.

- [ ] **Step 2: Lizenz erzeugen und Gerüst prüfen**

```bash
cd ~/dev/p5-www-idrac && dzil genlicense && git add -A && prove -lr t && dzil test
```

Expected: `LICENSE` existiert, `prove` meldet `Result: PASS`, `dzil test` endet mit `all's well`. `[@Author::GETTY]` sammelt über `Git::GatherDir` und sieht nur getrackte Dateien; deshalb das `git add` vor `dzil test`.

- [ ] **Step 3: Agenten-Team**

Skill `getty-agent-team` ausführen, Präfix `www-idrac`, Rollen `worker`, `test-writer`, `release-manager`, `doc-writer`. Vorlage sind die vier Agenten, die Regeln, `settings.json`, `skilletor.json` und `.claude/.gitignore` aus `p5-www-authentik` bei `3c9b5ac`. Was dort authentik-eigen ist, wird ersetzt:

| Bei authentik | Hier |
|---|---|
| „the synchronous Perl client for authentik (OIDC plus the REST API v3)“ | „the synchronous Perl client for Dell iDRAC (inventory, power, sensors and logs over Redfish)“ |
| Geschwister-Module `WWW::Authentik::OIDC` ↔ `::Admin` | `WWW::iDRAC::Redfish` ↔ die Fähigkeits-Klassen |
| öffentliche API `WWW::Authentik`, `::OIDC`, `::Admin` | `WWW::iDRAC`, `::Redfish`, `::System`, `::Power`, `::Sensors`, `::Logs`, `::Manager`, `::Capabilities` |
| Absätze zum Zwilling `p5-net-async-authentik` | entfallen; der Zwilling `Net::Async::iDRAC` existiert noch nicht. Ein Satz bleibt: Übersetzung und I/O getrennt halten, weil er kommt. |
| „Live tests hit a real Authentik. Opt-in via `AUTHENTIK_LIVE_TEST=1 AUTHENTIK_URL=…`“ | „Live tests hit a real server's management controller. Opt-in via `IDRAC_HOST`, `IDRAC_USERNAME`, `IDRAC_PASSWORD`; read-only. `IDRAC_LIVE_DESTRUCTIVE=1` switches the machine off and is never set by an agent.“ |
| Verweis auf Testmuster `t/60-oidc.t`, `t/50-admin.t` in `p5-www-keycloak` | Verweis auf `t/lib/FakeiDRAC.pm` und `t/lib/iDRACShapes.pm` |
| `briefing.skills: www-authentik-core` | `www-idrac-core` |

In die Regeln kommt zusätzlich, unter „Coordination“: „Fixtures are public. Nothing recorded from a real controller is committed before it went through `iDRACSanitize` and a person has read it.“

`.claude/skills/www-idrac-core/SKILL.md`:

```markdown
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
```

Die übrigen Skills kommen wie beim Geschwister über skilletor (`.claude/skilletor.json` unverändert übernehmen), danach:

```bash
cd ~/dev/p5-www-idrac && skilletor sync && skilletor check; echo "check rc=$?"
grep -rn -i 'authentik\|keycloak\|oidc' .claude/agents .claude/rules .claude/settings.json
for a in .claude/agents/*.md; do sed -n '/^briefing:/,/^---/p' "$a" | grep -E '^\s+- ' | sed 's/.*- //' | while read s; do ls .claude/skills/$s/SKILL.md ~/.claude/skills/$s/SKILL.md 2>/dev/null | head -1 | grep -q . || echo "MISSING in $a: $s"; done; done
```

Expected: `grep` findet höchstens den Verweis auf `~/dev/p5-www-keycloak` als Strukturvorbild; keine `MISSING`-Zeile. `skilletor check` darf mit rc=1 enden, wenn es nur Hinweise meldet; maßgeblich ist, dass jeder gebriefte Skill auflösbar ist.

- [ ] **Step 4: `CLAUDE.md`**

Der Einstieg im Gerüst-Zustand; Aufgabe 13 ersetzt ihn durch die endgültige Fassung.

````markdown
# CLAUDE.md

WWW::iDRAC — synchronous Perl client for Dell iDRAC: inventory, power, sensors, logs and
the controller itself, behind a facade cut by capability, not by protocol. Moo-based;
released to CPAN via Dist::Zilla `[@Author::GETTY]`.

Skeleton state: nothing is implemented yet. The design is
`docs/superpowers/specs/2026-10-04-www-idrac-design.md`, the plan
`docs/superpowers/plans/2026-10-04-www-idrac-phase-1.md`, the work is on the karr board.

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
dzil build           # build the distribution
dzil test            # test via Dist::Zilla
```

`LICENSE` is committed, not generated at build time; re-run `dzil genlicense` and
`git add LICENSE` after changing license, holder or year in `dist.ini`.
````

- [ ] **Step 5: Spec und Plan in die Dist holen**

```bash
cd ~/dev/p5-www-idrac
cp ~/dev/perl-developer/docs/superpowers/specs/2026-10-04-www-idrac-design.md docs/superpowers/specs/
cp ~/dev/perl-developer/docs/superpowers/plans/2026-10-04-www-idrac-phase-1.md docs/superpowers/plans/
```

In der Spec die Zeile `Status:` ersetzen durch `Status: freigegeben am 2026-10-04. Abschnitt 9 nennt, was erst am Gerät entschieden wird.` und Abschnitt 11 (Anlage) streichen; er ist mit dieser Aufgabe erledigt.

- [ ] **Step 6: Erster Commit der Dist**

```bash
cd ~/dev/p5-www-idrac && git add -A && git status --short && git commit -m "Add distribution skeleton and agent team"
```

Expected: Der Commit enthält keine Datei unter `tasks/`, kein `.karr`-Verzeichnis und keine `settings.local.json`.

- [ ] **Step 7: Board**

```bash
cd ~/dev/p5-www-idrac && karr init --name "WWW-iDRAC"
karr create --local-only --priority high --status todo --title "Observe iDRAC 7 and 8 live: transport, recorder, fixtures, sharpen the spec" \
  --body "Plan tasks 2 to 5 in docs/superpowers/plans/2026-10-04-www-idrac-phase-1.md. Task 5 needs Getty: addresses, credentials, and reading the recordings before they are committed."
karr create --local-only --priority high --status todo --title "Phase 1: facade, the five capability classes, capabilities, fixture test, live suite" \
  --body "Plan tasks 6 to 13. Tasks 6 to 11 do not wait for card 1; task 12 and the live run of task 13 do."
karr create --local-only --priority medium --status backlog --title "Phase 2: a second transport for what Redfish lacks on iDRAC 7/8" \
  --body "BIOS attributes, job queue, virtual media. WS-Man or racadm over SSH is decided by what card 1 measures (spec section 9). Brings the transport abstraction."
karr create --local-only --priority medium --status backlog --title "Net::Async::iDRAC: the async twin" \
  --body "Own repo p5-net-async-idrac, depends on WWW-iDRAC, reuses Role::HTTP's build_request/read_response and the *_from translations."
karr create --local-only --priority low --status backlog --title "Phase 3: iDRAC 9/10" \
  --body "Dell OEM actions, storage, firmware update. Only with such a controller at hand."
karr list
```

Expected: fünf Karten mit den IDs 1 bis 5, in dieser Reihenfolge. Die IDs nach dem Anlegen gegen `karr list` prüfen: `karr create` hat schon einmal still eine Karte überschrieben, als der Zähler nicht stimmte.

- [ ] **Step 8: Hub nachziehen**

```bash
cd ~/dev/perl-developer
git rm -q docs/superpowers/specs/2026-10-04-www-idrac-design.md docs/superpowers/plans/2026-10-04-www-idrac-phase-1.md
git commit -q -m "docs: WWW::iDRAC — Spec und Plan sind in die Dist p5-www-idrac umgezogen"
bin/fleet scan && bin/fleet --json repo p5-www-idrac | head -30
```

Expected: `fleet` kennt `p5-www-idrac` mit `dist_name` `WWW-iDRAC`, `status` `private`, `has_board` wahr und fünf Karten. `fleet.yml` braucht keinen Eintrag: Die Dist bleibt `standalone` und erbt `private`/`ours` aus den Voreinstellungen. Nur diese zwei Dateien committen; im Hub liegen fremde, nicht committete Änderungen.

---

### Task 2: Fehlerklassen und HTTP-Rolle

**Files:**
- Create: `lib/WWW/iDRAC/Error.pm`, `lib/WWW/iDRAC/Error/Validation.pm`, `lib/WWW/iDRAC/Error/Network.pm`, `lib/WWW/iDRAC/Error/API.pm`, `lib/WWW/iDRAC/Error/Unsupported.pm`
- Create: `lib/WWW/iDRAC/Role/HTTP.pm`
- Test: `t/10-errors.t`, `t/20-http.t`
- Modify: `t/00-load.t`

**Interfaces:**
- Produces: `WWW::iDRAC::Error->throw( message => ... )`; alle Fehler stringifizieren zu `message`.
- Produces: `WWW::iDRAC::Error::API` mit `http_status` (Pflicht), `message_id`, `api_message`, `resolution`, `is_not_found`, `is_unauthorized`.
- Produces: `WWW::iDRAC::Error::Unsupported` mit `capability` (Pflicht), `reason`.
- Produces: Rolle `WWW::iDRAC::Role::HTTP`, verlangt `ua`. `build_request( $method, $url, json => \%body, token => $token, basic => [ $user, $password ] )` → `HTTP::Request`; `read_response( $response, $method, $url )` → `{ status, data, location, token }` oder wirft `api_error_class`; `send_request( $method, $url, %arg )` → dasselbe, wirft `network_error_class`, wenn keine Antwort kam; `extended_info( $data )` → `{ message_id, message, resolution }`.

- [ ] **Step 1: Die Tests schreiben**

`t/10-errors.t`:

```perl
#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use WWW::iDRAC::Error;
use WWW::iDRAC::Error::API;
use WWW::iDRAC::Error::Network;
use WWW::iDRAC::Error::Unsupported;
use WWW::iDRAC::Error::Validation;

sub error_of (&) { my ( $code ) = @_; eval { $code->(); 1 } ? undef : $@ }

subtest 'classes and stringification' => sub {
  my $e = WWW::iDRAC::Error::API->new( message => 'boom', http_status => 404 );
  isa_ok( $e, 'WWW::iDRAC::Error' );
  is( "$e", 'boom', 'stringifies to the message' );
  ok( $e->is_not_found && !$e->is_unauthorized, 'predicates' );
  is( $e->message_id, undef, 'no message id unless given' );
  isa_ok( WWW::iDRAC::Error::Validation->new( message => 'x' ), 'WWW::iDRAC::Error' );
  isa_ok( WWW::iDRAC::Error::Network->new( message => 'x' ), 'WWW::iDRAC::Error' );
};

subtest 'throw' => sub {
  my $thrown = error_of { WWW::iDRAC::Error::Validation->throw( message => 'thrown' ) };
  isa_ok( $thrown, 'WWW::iDRAC::Error::Validation' );
  like( "$thrown", qr/\Athrown\z/, 'plain $@ matching keeps working' );
};

subtest 'unsupported' => sub {
  my $e = error_of { WWW::iDRAC::Error::Unsupported->throw( message => 'no', capability => 'power.cycle', reason => 'not offered' ) };
  isa_ok( $e, 'WWW::iDRAC::Error' );
  is( $e->capability, 'power.cycle', 'names the capability' );
  is( $e->reason, 'not offered', 'and the reason' );
  ok( !eval { WWW::iDRAC::Error::Unsupported->new( message => 'no' ); 1 }, 'the capability is required' );
};

done_testing;
```

`t/20-http.t`:

```perl
#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use HTTP::Response;
use LWP::UserAgent;
use MIME::Base64 qw( decode_base64 );

{
  package T::Client;
  use Moo;
  has ua => ( is => 'ro', default => sub { LWP::UserAgent->new( timeout => 2 ) } );
  with 'WWW::iDRAC::Role::HTTP';
}

my $client = T::Client->new;

sub error_of (&) { my ( $code ) = @_; eval { $code->(); 1 } ? undef : $@ }

sub answer {
  my ( $status, $body, @header ) = @_;
  return HTTP::Response->new( $status, 'Status', [ 'Content-Type' => 'application/json', @header ], $body );
}

subtest 'build_request' => sub {
  my $get = $client->build_request( GET => 'https://idrac.test/redfish/v1/', token => 'abc' );
  is( $get->method, 'GET', 'method' );
  is( $get->header('Accept'), 'application/json', 'asks for JSON' );
  is( $get->header('X-Auth-Token'), 'abc', 'the session token' );
  is( $get->header('Authorization'), undef, 'and no Basic credentials with it' );
  is( $get->content, '', 'no body' );

  my $post = $client->build_request( POST => 'https://idrac.test/x', json => { ResetType => 'On' } );
  is( $post->header('Content-Type'), 'application/json', 'a JSON body is announced' );
  is( $post->content, '{"ResetType":"On"}', 'and encoded' );

  my $basic = $client->build_request( GET => 'https://idrac.test/x', basic => [ 'root', "p\x{e4}ss:word" ] );
  my ( $encoded ) = $basic->header('Authorization') =~ /\ABasic (\S+)\z/;
  is( decode_base64($encoded), "root:p\xc3\xa4ss:word", 'Basic credentials, a non-ASCII password as UTF-8' );
  is( $basic->header('X-Auth-Token'), undef, 'no token header without a token' );
};

subtest 'read_response on success' => sub {
  my $result = $client->read_response( answer( 201, '{"Id":"7"}', 'X-Auth-Token' => 'tok', Location => '/redfish/v1/Sessions/7' ), POST => 'https://idrac.test/s' );
  is_deeply( $result, { status => 201, data => { Id => '7' }, location => '/redfish/v1/Sessions/7', token => 'tok' }, 'status, data, location and token' );
  my $empty = $client->read_response( HTTP::Response->new( 204, 'No Content' ), POST => 'https://idrac.test/a' );
  is_deeply( $empty, { status => 204, data => undef, location => undef, token => undef }, 'an answer without a body' );
};

subtest 'the shapes an error comes in' => sub {
  my $extended = error_of {
    $client->read_response( answer( 400, '{"error":{"code":"Base.1.0.GeneralError","message":"A general error has occurred.","@Message.ExtendedInfo":[{"MessageId":"IDRAC.1.6.SYS403","Message":"Unable to complete the operation.","Resolution":"Retry later."}]}}' ), POST => 'https://idrac.test/a' );
  };
  isa_ok( $extended, 'WWW::iDRAC::Error::API' );
  is( $extended->http_status, 400, 'status as a number' );
  is( $extended->message_id, 'IDRAC.1.6.SYS403', 'the message id of the extended information' );
  is( $extended->api_message, 'Unable to complete the operation.', 'its message' );
  is( $extended->resolution, 'Retry later.', 'its resolution' );
  like( "$extended", qr{\APOST https://idrac\.test/a failed: 400 Status - Unable to complete the operation\.\z}, 'the message names the request' );

  my $plain = error_of { $client->read_response( answer( 404, '{"error":{"code":"Base.1.0.GeneralError","message":"Not here."}}' ), GET => 'https://idrac.test/b' ) };
  is( $plain->message_id, 'Base.1.0.GeneralError', 'without extended information the code' );
  is( $plain->api_message, 'Not here.', 'and the message' );
  is( $plain->resolution, undef, 'and no resolution' );
  ok( $plain->is_not_found, 'is_not_found' );

  my $bare = error_of { $client->read_response( answer( 400, '{"@Message.ExtendedInfo":[{"MessageId":"X.1","Message":"Top level."}]}' ), GET => 'https://idrac.test/c' ) };
  is( $bare->message_id, 'X.1', 'extended information without the error wrapper' );

  for my $body ( '<html>Unauthorized</html>', '', '[1,2]', '"text"' ) {
    my $odd = error_of { $client->read_response( HTTP::Response->new( 401, 'Unauthorized', [], $body ), GET => 'https://idrac.test/d' ) };
    isa_ok( $odd, 'WWW::iDRAC::Error::API', 'body '.( length $body ? $body : '(empty)' ) );
    ok( $odd->is_unauthorized && !defined $odd->api_message, 'status kept, nothing invented' );
  }
};

subtest 'no answer at all' => sub {
  my $error = error_of { $client->send_request( GET => 'http://127.0.0.1:9/redfish/v1/', basic => [ 'root', 'sekrit-pw' ] ) };
  isa_ok( $error, 'WWW::iDRAC::Error::Network' );
  like( "$error", qr{\AGET http://127\.0\.0\.1:9/redfish/v1/: 500}, 'names the request' );
  unlike( "$error", qr/sekrit-pw/, 'and not the password' );
};

done_testing;
```

- [ ] **Step 2: Laufen lassen und scheitern sehen**

Run: `prove -l t/10-errors.t t/20-http.t`
Expected: FAIL, `Can't locate WWW/iDRAC/Error.pm in @INC` und `Can't locate WWW/iDRAC/Role/HTTP.pm`.

- [ ] **Step 3: Die Fehlerklassen**

`lib/WWW/iDRAC/Error.pm`:

```perl
package WWW::iDRAC::Error;

# ABSTRACT: Exception base class for WWW::iDRAC

use Moo;

# No namespace::autoclean here: it would remove the overload stub.
use overload '""' => sub { $_[0]->message }, fallback => 1;

our $VERSION = '0.001';

=synopsis

    use Scalar::Util qw( blessed );

    my $ok = eval { $idrac->power->cycle; 1 };
    if ( !$ok && blessed $@ && $@->isa('WWW::iDRAC::Error::Unsupported') ) { ... }

=description

Every error WWW::iDRAC raises is an object of one of four subclasses:
L<WWW::iDRAC::Error::Validation> for wrong arguments,
L<WWW::iDRAC::Error::Network> when no HTTP answer arrived,
L<WWW::iDRAC::Error::API> when the iDRAC answered with an error, and
L<WWW::iDRAC::Error::Unsupported> when this controller does not have what was
asked for. All of them stringify to their message, so plain C<$@> matching
keeps working.

=cut

has message => (
  is       => 'ro',
  required => 1
);

=attr message

The human-readable description. The object stringifies to it.

=cut

sub throw {
  my ( $class, %arg ) = @_;
  die $class->new(%arg);
}

=method throw

    WWW::iDRAC::Error::Validation->throw( message => 'host is required' );

Builds the exception and dies with it.

=cut

1;
```

`lib/WWW/iDRAC/Error/Validation.pm`:

```perl
package WWW::iDRAC::Error::Validation;

# ABSTRACT: Raised for arguments WWW::iDRAC cannot work with

use Moo;
extends 'WWW::iDRAC::Error';

our $VERSION = '0.001';

1;
```

`lib/WWW/iDRAC/Error/Network.pm`:

```perl
package WWW::iDRAC::Error::Network;

# ABSTRACT: Raised when the iDRAC could not be reached, TLS failures included

use Moo;
extends 'WWW::iDRAC::Error';

our $VERSION = '0.001';

1;
```

`lib/WWW/iDRAC/Error/API.pm`:

```perl
package WWW::iDRAC::Error::API;

# ABSTRACT: Raised when the iDRAC answers with an HTTP error

use Moo;
extends 'WWW::iDRAC::Error';

our $VERSION = '0.001';

=description

Redfish reports an error as C<< {"error": {"code", "message",
"@Message.ExtendedInfo": [...]}} >>. The first entry of the extended
information is what Dell fills with the useful part, and it ends up in
L</message_id>, L</api_message> and L</resolution>.

=cut

has http_status => (
  is       => 'ro',
  required => 1
);

=attr http_status

The HTTP status code as a number, for example 404.

=cut

has message_id => ( is => 'ro' );

=attr message_id

Dell's identifier of the message, for example C<IDRAC.1.6.SYS403>, when the
iDRAC sent one.

=cut

has api_message => ( is => 'ro' );

=attr api_message

What the iDRAC said, if it said anything.

=cut

has resolution => ( is => 'ro' );

=attr resolution

What Dell suggests doing about it, if the iDRAC sent a suggestion.

=cut

sub is_not_found    { $_[0]->http_status == 404 ? 1 : 0 }
sub is_unauthorized { $_[0]->http_status == 401 ? 1 : 0 }

=method is_not_found

=method is_unauthorized

True for status 404 and 401.

=cut

1;
```

`lib/WWW/iDRAC/Error/Unsupported.pm`:

```perl
package WWW::iDRAC::Error::Unsupported;

# ABSTRACT: Raised when this iDRAC does not have what was asked for

use Moo;
extends 'WWW::iDRAC::Error';

our $VERSION = '0.001';

=description

Thrown by the capability classes, before anything is sent, when the
controller does not offer the resource or the action a method needs. What a
controller offers depends on its generation, its firmware and its license.

=cut

has capability => (
  is       => 'ro',
  required => 1
);

=attr capability

The name of the method that cannot be served, as C<area.method>, for example
C<power.cycle>. The same names go into
L<WWW::iDRAC::Capabilities/supports>.

=cut

has reason => ( is => 'ro' );

=attr reason

What exactly is missing.

=cut

1;
```

- [ ] **Step 4: Die HTTP-Rolle**

`lib/WWW/iDRAC/Role/HTTP.pm`:

```perl
package WWW::iDRAC::Role::HTTP;

# ABSTRACT: Sending requests to an iDRAC and turning failures into exceptions

use HTTP::Request;
use JSON::MaybeXS;
use MIME::Base64 qw( encode_base64 );
use WWW::iDRAC::Error::API;
use WWW::iDRAC::Error::Network;
use Moo::Role;

our $VERSION = '0.001';

requires 'ua';

=description

One L<LWP::UserAgent>, JSON in and out, and the mapping of Redfish's error
document onto L<WWW::iDRAC::Error::API>. L</build_request> and
L</read_response> do no I/O, so an asynchronous client can use them as they
are and replace only L</send_request>.

=cut

sub json_codec { JSON::MaybeXS->new( utf8 => 1, canonical => 1 ) }

sub api_error_class     { 'WWW::iDRAC::Error::API' }
sub network_error_class { 'WWW::iDRAC::Error::Network' }

=method json_codec

The JSON encoder and decoder.

=method api_error_class

=method network_error_class

The classes the errors are thrown as. An asynchronous client overrides them
with its own subclasses.

=cut

sub build_request {
  my ( $self, $method, $url, %arg ) = @_;
  my $request = HTTP::Request->new( $method => $url );
  $request->header( Accept => 'application/json' );
  $request->header( 'X-Auth-Token' => $arg{token} ) if defined $arg{token};
  if ( $arg{basic} ) {
    # credentials are characters, as they are for the JSON body of a session login
    my $pair = join ':', @{ $arg{basic} };
    utf8::encode($pair);
    $request->header( Authorization => 'Basic '.encode_base64( $pair, '' ) );
  }
  if ( exists $arg{json} ) {
    $request->header( 'Content-Type' => 'application/json' );
    $request->content( $self->json_codec->encode( $arg{json} ) );
  }
  return $request;
}

=method build_request

    my $request = $self->build_request( POST => $url, json => \%body, token => $token );
    my $request = $self->build_request( GET => $url, basic => [ $username, $password ] );

The L<HTTP::Request> for one call: JSON accepted, the session token or the
Basic credentials when given, the body as JSON.

=cut

sub extended_info {
  my ( $self, $data ) = @_;
  return {} unless ref $data eq 'HASH';
  my $error = ref $data->{error} eq 'HASH' ? $data->{error} : $data;
  my $list  = $error->{'@Message.ExtendedInfo'};
  my ( $first ) = grep { ref $_ eq 'HASH' } ref $list eq 'ARRAY' ? @$list : ();
  return {
    message_id => $first ? $first->{MessageId} : $error->{code},
    message    => ( $first ? $first->{Message} : undef ) // $error->{message},
    resolution => $first ? $first->{Resolution} : undef
  };
}

=method extended_info

    my $info = $self->extended_info($data);

C<message_id>, C<message> and C<resolution> out of a Redfish error document:
the first entry of C<@Message.ExtendedInfo> when there is one, the plain
C<code> and C<message> otherwise.

=cut

sub read_response {
  my ( $self, $response, $method, $url ) = @_;
  # decoded_content undoes a Content-Encoding, the raw content does not; with
  # charset => 'none' the bytes stay bytes, which the JSON codec decodes itself
  my $content = $response->decoded_content( charset => 'none' ) // '';
  my $data    = length $content ? eval { $self->json_codec->decode($content) } : undef;
  return {
    status   => $response->code,
    data     => $data,
    location => scalar $response->header('Location'),
    token    => scalar $response->header('X-Auth-Token')
  } if $response->is_success;
  my $info = $self->extended_info($data);
  $self->api_error_class->throw(
    message     => $method.' '.$url.' failed: '.$response->status_line.( defined $info->{message} ? ' - '.$info->{message} : '' ),
    http_status => $response->code,
    message_id  => $info->{message_id},
    api_message => $info->{message},
    resolution  => $info->{resolution}
  );
}

=method read_response

    my $result = $self->read_response( $response, $method, $url );

Turns an L<HTTP::Response> into C<status>, the decoded C<data>, the
C<location> header and the C<token> from C<X-Auth-Token>, or throws
L</api_error_class> for any status that is not a success.

=cut

sub send_request {
  my ( $self, $method, $url, %arg ) = @_;
  my $response = $self->ua->request( $self->build_request( $method, $url, %arg ) );
  $self->network_error_class->throw( message => $method.' '.$url.': '.$response->status_line )
    if $response->code == 500 && ( $response->header('Client-Warning') // '' ) eq 'Internal response';
  return $self->read_response( $response, $method, $url );
}

=method send_request

    my $result = $self->send_request( POST => $url, json => \%body, token => $token );

Sends one request. Throws L<WWW::iDRAC::Error::Network> when no answer came
back, a refused certificate included, and L<WWW::iDRAC::Error::API> for an
error status. Neither message contains the password.

=cut

1;
```

Zugangsdaten sind Zeichen, nicht Bytes: Für Basic werden sie immer als UTF-8 kodiert, so wie der JSON-Codec es beim Session-Login mit dem Passwort tut. Sonst hinge es von der Anmeldeart ab, ob ein Passwort mit Umlaut funktioniert.

- [ ] **Step 5: `t/00-load.t` ergänzen**

`t/00-load.t`:

```perl
#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

for (qw(
  WWW::iDRAC
  WWW::iDRAC::Error
  WWW::iDRAC::Error::API
  WWW::iDRAC::Error::Network
  WWW::iDRAC::Error::Unsupported
  WWW::iDRAC::Error::Validation
  WWW::iDRAC::Role::HTTP
)) {
  use_ok($_);
}

done_testing;
```

- [ ] **Step 6: Laufen lassen**

Run: `prove -lr t`
Expected: PASS, 3 Dateien.

- [ ] **Step 7: Übergabe**

Commit-fertiger Baum an `www-idrac-release-manager`. Vorschlag: `Add the error classes and the HTTP role`.

---

### Task 3: Nachgebauter iDRAC und Redfish-Transport

**Files:**
- Create: `lib/WWW/iDRAC/Redfish.pm`
- Create: `t/lib/FakeiDRAC.pm`
- Test: `t/30-redfish.t`
- Modify: `t/00-load.t`

**Interfaces:**
- Consumes: `WWW::iDRAC::Role::HTTP`, `WWW::iDRAC::Error::API`, `WWW::iDRAC::Error::Validation` (Aufgabe 2).
- Produces: `WWW::iDRAC::Redfish->new( base_url => 'https://host', username =>, password =>, ua =>, session => 1 )`.
- Produces: `get($path)`, `post( $path, \%body )`, `patch( $path, \%body )`, `delete($path)` → dekodiertes Dokument oder `undef`; `request( $method, $path, json => \%body )` → `{ status, data, location, token }`.
- Produces: `members( $path, limit => $n )` → Liste von Dokumenten in der Reihenfolge des Controllers.
- Produces: `locate($kind)` mit `$kind` aus `Systems`, `Chassis`, `Managers` → Pfad oder `undef`, gemerkt.
- Produces: `root` → Service-Root; `login`, `logout` → 1 wenn eine Session beendet wurde, sonst 0; `forget_session`; `url($path)`; `path_of($address)`.
- Produces: `FakeiDRAC->new( docs => \%docs, delay => $n )`, `FakeiDRAC->from_file($file)`, `->host`, `->requests`, `->sessions`, `->doc($path)`, `->remove($path)`, `->forget_tokens`, `->seen($regex)` → Liste von `"METHOD path"`, `->default_docs`. Anmeldung `root` / `calvin`.

- [ ] **Step 1: Den nachgebauten iDRAC schreiben**

`t/lib/FakeiDRAC.pm`. Die Standard-Dokumente haben die Form eines 13G-Servers mit erfundenen Werten; sie sind keine Aufnahme. Absichtlich enthalten: eine Chassis-Collection, deren erster Eintrag nicht das Chassis des Systems ist; ein Sensor ohne Messwert; ein Log mit ganzen Einträgen in falscher Reihenfolge und eines mit Verweisen und zweiter Seite; kein `PowerCycle` in den erlaubten Reset-Typen; keine Memory-Collection.

```perl
package FakeiDRAC;

# An in-memory stand-in for the Redfish service of an iDRAC, used as the
# LWP::UserAgent of the code under test.
#
#   my $fake  = FakeiDRAC->new;                                        # the invented controller below
#   my $fake  = FakeiDRAC->from_file('t/fixtures/idrac8/redfish.json'); # a recorded one
#   my $idrac = WWW::iDRAC->new( host => $fake->host, username => 'root', password => 'calvin', ua => $fake );
#
# The documents are a map of path to document. What the fake does with them
# is only what Redfish itself prescribes: the service root is readable
# without a login, everything else wants a session token or Basic
# credentials, a session is created with a POST to the collection the service
# root names, and an action is a POST to its target.
#
# default_docs has the shape of a 13th generation server, with invented
# values. It is not a recording. What a real iDRAC 7 or 8 answers is in
# t/fixtures/, and t/85-fixtures.t runs every capability against those.

use strict;
use warnings;
use parent 'LWP::UserAgent';
use HTTP::Response;
use JSON::MaybeXS;
use MIME::Base64 qw( decode_base64 );
use URI;

my $JSON = JSON::MaybeXS->new( utf8 => 1, canonical => 1 );

sub new {
  my ( $class, %arg ) = @_;
  my $self = $class->SUPER::new;
  %$self = (
    %$self,
    host     => 'idrac.test',
    docs     => $arg{docs} || $class->default_docs,
    username => 'root',
    password => 'calvin',
    tokens   => {},
    requests => [],
    seq      => 0,
    delay    => $arg{delay} // 0,
    pending  => undef
  );
  return $self;
}

sub from_file {
  my ( $class, $file, %arg ) = @_;
  open my $fh, '<:raw', $file or die 'cannot read '.$file.': '.$!;
  my $docs = $JSON->decode( do { local $/; <$fh> } );
  return $class->new( %arg, docs => $docs );
}

sub host     { $_[0]{host} }
sub requests { $_[0]{requests} }
sub sessions { scalar keys %{ $_[0]{tokens} } }

# the document at a path, to change it in a test
sub doc { $_[0]{docs}{ $_[1] } }

sub remove { delete $_[0]{docs}{ $_[1] }; return }

# what a restart of the controller does to the sessions it handed out
sub forget_tokens { $_[0]{tokens} = {}; return }

# the requests that match, as "METHOD path"
sub seen {
  my ( $self, $pattern ) = @_;
  return grep { $_ =~ $pattern } map { $_->method.' '.URI->new( $_->uri )->path_query } @{ $self->{requests} };
}

sub _reply {
  my ( $self, $status, $data, %header ) = @_;
  my $response = HTTP::Response->new( $status, $status < 300 ? 'OK' : 'Error' );
  $response->header(%header) if %header;
  if ( defined $data ) {
    $response->header( 'Content-Type' => 'application/json' );
    $response->content( $JSON->encode($data) );
  }
  return $response;
}

sub _error {
  my ( $self, $status, $id, $message, $resolution ) = @_;
  return $self->_reply( $status, {
    error => {
      code                    => 'Base.1.0.GeneralError',
      message                 => 'A general error has occurred. See ExtendedInfo for more information.',
      '@Message.ExtendedInfo' => [ { MessageId => $id, Message => $message, Resolution => $resolution, Severity => 'Warning' } ]
    }
  } );
}

sub _key {
  my ( $self, $path ) = @_;
  $path =~ s{/+\z}{} unless $path eq '/';
  return $path;
}

sub _authorized {
  my ( $self, $request ) = @_;
  my $token = $request->header('X-Auth-Token');
  return 1 if defined $token && $self->{tokens}{$token};
  my ( $basic ) = ( $request->header('Authorization') // '' ) =~ /\ABasic (.+)\z/;
  return defined $basic && decode_base64($basic) eq $self->{username}.':'.$self->{password} ? 1 : 0;
}

sub _sessions_path {
  my ( $self ) = @_;
  my $root = $self->{docs}{'/redfish/v1'} || {};
  return $root->{Links} && $root->{Links}{Sessions} ? $root->{Links}{Sessions}{'@odata.id'} : undef;
}

# the action whose target is this path, as ( name, action, document that offers it )
sub _action {
  my ( $self, $path ) = @_;
  for my $doc ( values %{ $self->{docs} } ) {
    next unless ref $doc eq 'HASH' && ref $doc->{Actions} eq 'HASH';
    for my $name ( keys %{ $doc->{Actions} } ) {
      my $action = $doc->{Actions}{$name};
      return ( $name, $action, $doc ) if ref $action eq 'HASH' && ( $action->{target} // '' ) eq $path;
    }
  }
  return;
}

sub request {
  my ( $self, $request ) = @_;
  push @{ $self->{requests} }, $request;
  my $uri    = URI->new( $request->uri );
  my $path   = $self->_key( $uri->path_query );
  my $method = $request->method;
  my $body   = length( $request->content // '' ) ? $JSON->decode( $request->content ) : undef;

  return $self->_reply( 200, $self->{docs}{'/redfish/v1'} ) if $method eq 'GET' && $path eq '/redfish/v1';

  my $sessions = $self->_sessions_path;
  if ( defined $sessions && $method eq 'POST' && $path eq $sessions ) {
    return $self->_error( 401, 'IDRAC.1.6.SYS415', 'Unable to complete the operation because the username or password is not correct.', 'Enter valid credentials and retry the operation.' )
      unless ( $body->{UserName} // '' ) eq $self->{username} && ( $body->{Password} // '' ) eq $self->{password};
    my $id    = ++$self->{seq};
    my $token = 'token-'.$id;
    $self->{tokens}{$token} = $id;
    return $self->_reply( 201, { '@odata.id' => $sessions.'/'.$id, Id => "$id", UserName => $self->{username} },
      'X-Auth-Token' => $token, Location => 'https://'.$self->{host}.$sessions.'/'.$id );
  }

  return $self->_error( 401, 'Base.1.0.AccessDenied', 'The authentication credentials included with this request are missing or invalid.', 'Log in again.' )
    unless $self->_authorized($request);

  if ( defined $sessions && $method eq 'DELETE' && $path =~ m{\A\Q$sessions\E/(\d+)\z} ) {
    my $id = $1;
    delete $self->{tokens}{$_} for grep { $self->{tokens}{$_} == $id } keys %{ $self->{tokens} };
    return $self->_reply(204);
  }

  if ( $method eq 'GET' ) {
    my $doc = $self->{docs}{$path}
      or return $self->_error( 404, 'Base.1.0.ResourceMissingAtURI', 'The resource at the URI '.$path.' was not found.', 'Check the URI and retry.' );
    if ( $self->{pending} && $path eq $self->{pending}{path} && --$self->{pending}{after} < 0 ) {
      $doc->{PowerState} = $self->{pending}{state};
      $self->{pending} = undef;
    }
    return $self->_reply( 200, $doc );
  }

  if ( $method eq 'POST' ) {
    my ( $name, $action, $owner ) = $self->_action($path)
      or return $self->_error( 404, 'Base.1.0.ResourceMissingAtURI', 'The resource at the URI '.$path.' was not found.', 'Check the URI and retry.' );
    if ( $name eq '#ComputerSystem.Reset' || $name eq '#Manager.Reset' ) {
      my $type    = $body->{ResetType} // '';
      my $allowed = $action->{'ResetType@Redfish.AllowableValues'};
      return $self->_error( 400, 'Base.1.0.ActionParameterNotSupported', 'The parameter ResetType for the action is not supported: '.$type, 'Use one of the allowable values.' )
        if $allowed && !grep { $_ eq $type } @$allowed;
      if ( $name eq '#Manager.Reset' ) {
        $self->forget_tokens;
        return $self->_reply(204);
      }
      my $state = $type =~ /\A(?:ForceOff|GracefulShutdown)\z/ ? 'Off' : 'On';
      if ( $self->{delay} ) { $self->{pending} = { path => $self->_key( $owner->{'@odata.id'} ), state => $state, after => $self->{delay} } }
      else                  { $owner->{PowerState} = $state }
      return $self->_reply(204);
    }
    if ( $name eq '#LogService.ClearLog' ) {
      my $entries = $self->{docs}{ $self->_key( $owner->{Entries}{'@odata.id'} ) };
      @$entries{ 'Members', 'Members@odata.count' } = ( [], 0 ) if $entries;
      return $self->_reply(204);
    }
    return $self->_reply(204);
  }

  return $self->_error( 405, 'Base.1.0.GeneralError', 'Method not allowed.', 'Use a supported method.' );
}

sub default_docs {
  my $system  = '/redfish/v1/Systems/System.Embedded.1';
  my $chassis = '/redfish/v1/Chassis/System.Embedded.1';
  my $manager = '/redfish/v1/Managers/iDRAC.Embedded.1';
  my $ref     = sub { { '@odata.id' => $_[0] } };
  my $ok      = { Health => 'OK', State => 'Enabled' };
  return {
    '/redfish/v1' => {
      '@odata.id'    => '/redfish/v1',
      RedfishVersion => '1.0.2',
      Systems        => $ref->('/redfish/v1/Systems'),
      Chassis        => $ref->('/redfish/v1/Chassis'),
      Managers       => $ref->('/redfish/v1/Managers'),
      Links          => { Sessions => $ref->('/redfish/v1/Sessions') }
    },
    '/redfish/v1/Systems'  => { Members => [ $ref->($system) ],  'Members@odata.count' => 1 },
    '/redfish/v1/Chassis'  => { Members => [ $ref->('/redfish/v1/Chassis/Enclosure.Internal.0-1'), $ref->($chassis) ], 'Members@odata.count' => 2 },
    '/redfish/v1/Managers' => { Members => [ $ref->($manager) ], 'Members@odata.count' => 1 },
    $system => {
      '@odata.id'        => $system,
      Manufacturer       => 'Dell Inc.',
      Model              => 'PowerEdge T330',
      SKU                => 'TAG0001',
      SerialNumber       => 'SERIAL0001',
      UUID               => '00000000-0000-0000-0000-000000000001',
      AssetTag           => '',
      HostName           => 'server.example.org',
      BiosVersion        => '2.4.3',
      PowerState         => 'On',
      Status             => $ok,
      ProcessorSummary   => { Count => 1, Model => 'Intel(R) Xeon(R) CPU E3-1230 v5 @ 3.40GHz' },
      MemorySummary      => { TotalSystemMemoryGiB => 32 },
      Processors         => $ref->( $system.'/Processors' ),
      EthernetInterfaces => $ref->( $system.'/EthernetInterfaces' ),
      Links              => { Chassis => [ $ref->($chassis) ], ManagedBy => [ $ref->($manager) ] },
      Actions            => {
        '#ComputerSystem.Reset' => {
          target                              => $system.'/Actions/ComputerSystem.Reset',
          'ResetType@Redfish.AllowableValues' => [qw( On ForceOff GracefulRestart GracefulShutdown PushPowerButton Nmi )]
        }
      }
    },
    $system.'/Processors'              => { Members => [ $ref->( $system.'/Processors/CPU.Socket.1' ) ], 'Members@odata.count' => 1 },
    $system.'/Processors/CPU.Socket.1' => {
      '@odata.id' => $system.'/Processors/CPU.Socket.1',
      Id          => 'CPU.Socket.1',
      Socket      => 'CPU.Socket.1',
      Model       => 'Intel(R) Xeon(R) CPU E3-1230 v5 @ 3.40GHz',
      TotalCores  => 4,
      TotalThreads => 8,
      MaxSpeedMHz => 4000,
      Status      => $ok
    },
    $system.'/EthernetInterfaces' => {
      Members => [ $ref->( $system.'/EthernetInterfaces/NIC.Embedded.1-1-1' ), $ref->( $system.'/EthernetInterfaces/NIC.Embedded.2-1-1' ) ],
      'Members@odata.count' => 2
    },
    $system.'/EthernetInterfaces/NIC.Embedded.1-1-1' => {
      '@odata.id' => $system.'/EthernetInterfaces/NIC.Embedded.1-1-1',
      Id          => 'NIC.Embedded.1-1-1',
      MACAddress  => '00:00:5E:00:53:01',
      SpeedMbps   => 1000,
      LinkStatus  => 'LinkUp',
      Status      => $ok
    },
    $system.'/EthernetInterfaces/NIC.Embedded.2-1-1' => {
      '@odata.id'         => $system.'/EthernetInterfaces/NIC.Embedded.2-1-1',
      Id                  => 'NIC.Embedded.2-1-1',
      PermanentMACAddress => '00:00:5E:00:53:02',
      SpeedMbps           => undef,
      LinkStatus          => 'LinkDown',
      Status              => { Health => undef, State => 'Enabled' }
    },
    '/redfish/v1/Chassis/Enclosure.Internal.0-1' => { '@odata.id' => '/redfish/v1/Chassis/Enclosure.Internal.0-1', Id => 'Enclosure.Internal.0-1' },
    $chassis => {
      '@odata.id' => $chassis,
      Id          => 'System.Embedded.1',
      Thermal     => $ref->( $chassis.'/Thermal' ),
      Power       => $ref->( $chassis.'/Power' )
    },
    $chassis.'/Thermal' => {
      Temperatures => [
        {
          Name                      => 'System Board Inlet Temp',
          ReadingCelsius            => 23,
          UpperThresholdNonCritical => 42,
          UpperThresholdCritical    => 47,
          LowerThresholdNonCritical => 3,
          LowerThresholdCritical    => -7,
          Status                    => $ok
        },
        # a sensor the controller lists without a reading
        { Name => 'CPU2 Temp', ReadingCelsius => undef, Status => { Health => undef, State => 'Absent' } }
      ],
      Fans => [
        { FanName => 'System Board Fan1', Reading => 4800, ReadingUnits => 'RPM', Status => $ok },
        { Name    => 'System Board Fan2', Reading => 0,    ReadingUnits => 'RPM', Status => { Health => 'Critical', State => 'Enabled' } }
      ]
    },
    $chassis.'/Power' => {
      PowerControl => [ {
        PowerConsumedWatts => 87,
        PowerCapacityWatts => 495,
        PowerMetrics       => { AverageConsumedWatts => 84, MinConsumedWatts => 61, MaxConsumedWatts => 143 }
      } ],
      Voltages => [
        { Name => 'PS1 Voltage 1', ReadingVolts => 230, Status => $ok },
        { Name => 'System Board 3.3V PG', ReadingVolts => undef, Status => $ok }
      ],
      PowerSupplies => [ {
        Name                 => 'PS1 Status',
        Model                => 'PWR SPLY,495W,RDNT,DELTA  ',
        SerialNumber         => 'SERIAL0002',
        FirmwareVersion      => '00.1D.7D',
        PowerCapacityWatts   => 495,
        LineInputVoltage     => 230,
        LastPowerOutputWatts => 87,
        Status               => { Health => 'Warning', State => 'Enabled' }
      } ]
    },
    $manager => {
      '@odata.id'        => $manager,
      Id                 => 'iDRAC.Embedded.1',
      Model              => '13G Monolithic',
      FirmwareVersion    => '2.83.83.83',
      DateTime           => '2026-10-04T12:00:00+02:00',
      UUID               => '00000000-0000-0000-0000-000000000002',
      Status             => $ok,
      LogServices        => $ref->( $manager.'/LogServices' ),
      EthernetInterfaces => $ref->( $manager.'/EthernetInterfaces' ),
      Actions            => {
        '#Manager.Reset' => { target => $manager.'/Actions/Manager.Reset', 'ResetType@Redfish.AllowableValues' => ['GracefulRestart'] }
      }
    },
    $manager.'/EthernetInterfaces'               => { Members => [ $ref->( $manager.'/EthernetInterfaces/iDRAC.Embedded.1%23NIC.1' ) ], 'Members@odata.count' => 1 },
    $manager.'/EthernetInterfaces/iDRAC.Embedded.1%23NIC.1' => {
      Id            => 'iDRAC.Embedded.1#NIC.1',
      HostName      => 'idrac-TAG0001',
      FQDN          => 'idrac-TAG0001.example.org',
      MACAddress    => '00:00:5E:00:53:10',
      IPv4Addresses => [ { Address => '192.0.2.10', SubnetMask => '255.255.255.0', Gateway => '192.0.2.1', AddressOrigin => 'Static' } ],
      IPv6Addresses => [ { Address => '2001:db8::10', PrefixLength => 64 }, { Address => '::', PrefixLength => 0 } ],
      NameServers   => [ '192.0.2.53', '0.0.0.0', '::' ]
    },
    $manager.'/LogServices' => { Members => [ $ref->( $manager.'/LogServices/Sel' ), $ref->( $manager.'/LogServices/Lclog' ) ], 'Members@odata.count' => 2 },
    $manager.'/LogServices/Sel' => {
      '@odata.id' => $manager.'/LogServices/Sel',
      Id          => 'Sel',
      Entries     => $ref->( $manager.'/Logs/Sel' ),
      Actions     => { '#LogService.ClearLog' => { target => $manager.'/LogServices/Sel/Actions/LogService.ClearLog' } }
    },
    $manager.'/LogServices/Lclog' => { '@odata.id' => $manager.'/LogServices/Lclog', Id => 'Lclog', Entries => $ref->( $manager.'/Logs/Lclog' ) },
    # the whole entries inside the collection, and not in order
    $manager.'/Logs/Sel' => {
      'Members@odata.count' => 3,
      Members               => [
        { '@odata.id' => $manager.'/Logs/Sel/2', Id => '2', Created => '2026-10-02T08:00:00+02:00', Severity => 'Critical', Message => 'Fan 2 failed.', MessageId => 'FAN0001' },
        { '@odata.id' => $manager.'/Logs/Sel/3', Id => '3', Created => '2026-10-03T09:30:00+02:00', Severity => 'OK', Message => 'Fan 2 was restored.', MessageId => 'FAN0002' },
        { '@odata.id' => $manager.'/Logs/Sel/1', Id => '1', Created => '2026-10-01T07:00:00+02:00', Severity => 'Warning', Message => 'The chassis is open.', MessageId => 'SEC0000' }
      ]
    },
    # only addresses inside the collection, and a second page
    $manager.'/Logs/Lclog' => {
      'Members@odata.count'    => 3,
      Members                  => [ $ref->( $manager.'/Logs/Lclog/3' ), $ref->( $manager.'/Logs/Lclog/2' ) ],
      'Members@odata.nextLink' => $manager.'/Logs/Lclog?$skip=2'
    },
    $manager.'/Logs/Lclog?$skip=2' => { 'Members@odata.count' => 3, Members => [ $ref->( $manager.'/Logs/Lclog/1' ) ] },
    $manager.'/Logs/Lclog/3' => { Id => '3', Created => '2026-10-03T10:00:00+02:00', Severity => 'OK', Message => 'Successfully logged in.', MessageId => 'USR0030' },
    $manager.'/Logs/Lclog/2' => { Id => '2', Created => '2026-10-02T10:00:00+02:00', Severity => 'OK', Message => 'The system was turned on.', MessageId => 'SYS1000' },
    $manager.'/Logs/Lclog/1' => { Id => '1', Created => '2026-10-01T10:00:00+02:00', Severity => 'Informational', Message => 'The Lifecycle log was archived.', MessageId => 'LOG007' }
  };
}

1;
```

- [ ] **Step 2: Den Test schreiben**

`t/30-redfish.t`:

```perl
#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';

use FakeiDRAC;
use WWW::iDRAC::Redfish;

sub error_of (&) { my ( $code ) = @_; eval { $code->(); 1 } ? undef : $@ }

sub transport {
  my ( $fake, %arg ) = @_;
  return WWW::iDRAC::Redfish->new( base_url => 'https://'.$fake->host, username => 'root', password => 'calvin', ua => $fake, %arg );
}

my $system  = '/redfish/v1/Systems/System.Embedded.1';
my $manager = '/redfish/v1/Managers/iDRAC.Embedded.1';

subtest 'the first request logs in' => sub {
  my $fake    = FakeiDRAC->new;
  my $redfish = transport($fake);
  is( $fake->sessions, 0, 'nothing happens before the first request' );
  is( $redfish->get($system)->{Model}, 'PowerEdge T330', 'get returns the document' );
  is_deeply( [ $fake->seen(qr/./) ], [ 'GET /redfish/v1/', 'POST /redfish/v1/Sessions', 'GET '.$system ], 'service root, login, request' );
  is( $fake->requests->[0]->header('Authorization'), undef, 'the service root is read without credentials' );
  $redfish->get($system);
  is( scalar $fake->seen(qr/\APOST/), 1, 'one login for many requests' );
  is( $fake->sessions, 1, 'one session' );
};

subtest 'logout' => sub {
  my $fake    = FakeiDRAC->new;
  my $redfish = transport($fake);
  is( $redfish->logout, 0, 'nothing to end before a login' );
  $redfish->get($system);
  is( $redfish->logout, 1, 'ends the session' );
  is( $fake->sessions, 0, 'the controller has none left' );
  is_deeply( [ $fake->seen(qr/\ADELETE/) ], ['DELETE /redfish/v1/Sessions/1'], 'at the address the login was answered with' );
  $redfish->get($system);
  is( $fake->sessions, 1, 'the next request logs in again' );
};

subtest 'a session is ended when the object goes away' => sub {
  my $fake = FakeiDRAC->new;
  {
    my $redfish = transport($fake);
    $redfish->get($system);
    is( $fake->sessions, 1, 'open inside the scope' );
  }
  is( $fake->sessions, 0, 'ended at the end of the scope' );

  my $gone = FakeiDRAC->new;
  {
    my $redfish = transport($gone);
    $redfish->get($system);
    $gone->forget_tokens;
    local $@ = 'untouched';
    undef $redfish;
    is( $@, 'untouched', 'a logout the controller refuses does not die and leaves $@ alone' );
  }
};

subtest 'a refused token is renewed once' => sub {
  my $fake    = FakeiDRAC->new;
  my $redfish = transport($fake);
  $redfish->get($system);
  $fake->forget_tokens;
  is( $redfish->get($system)->{Model}, 'PowerEdge T330', 'the request succeeds after a restart of the controller' );
  is( scalar $fake->seen(qr/\APOST/), 2, 'with exactly one more login' );
};

subtest 'wrong credentials' => sub {
  my $fake    = FakeiDRAC->new;
  my $redfish = transport( $fake, password => 'wrong-pw' );
  my $error   = error_of { $redfish->get($system) };
  isa_ok( $error, 'WWW::iDRAC::Error::API' );
  ok( $error->is_unauthorized, 'refused as unauthorized' );
  is( $error->message_id, 'IDRAC.1.6.SYS415', 'with the message id of the controller' );
  unlike( "$error", qr/wrong-pw/, 'the message does not contain the password' );
  is( scalar $fake->seen(qr/\APOST/), 1, 'one attempt, no loop' );
};

subtest 'without a session' => sub {
  my $fake    = FakeiDRAC->new;
  my $redfish = transport( $fake, session => 0 );
  is( $redfish->get($system)->{Model}, 'PowerEdge T330', 'Basic credentials are accepted' );
  is( scalar $fake->seen(qr/\APOST/), 0, 'no login' );
  is( $redfish->logout, 0, 'and nothing to end' );
  my $error = error_of { transport( $fake, session => 0, password => 'wrong-pw' )->get($system) };
  ok( $error->is_unauthorized, 'wrong credentials are a plain 401' );
};

subtest 'the four verbs' => sub {
  my $fake    = FakeiDRAC->new;
  my $redfish = transport($fake);
  is( $redfish->post( $system.'/Actions/ComputerSystem.Reset', { ResetType => 'ForceOff' } ), undef, 'post returns the document, here none' );
  is( $fake->doc($system)->{PowerState}, 'Off', 'the body arrived' );
  is( $fake->requests->[-1]->content, '{"ResetType":"ForceOff"}', 'as JSON' );
  my $refused = error_of { $redfish->post( $system.'/Actions/ComputerSystem.Reset', { ResetType => 'PowerCycle' } ) };
  is( $refused->http_status, 400, 'an error status is an API error' );
  like( $refused->api_message, qr/not supported: PowerCycle/, 'with what the controller said' );
  my $missing = error_of { $redfish->get('/redfish/v1/Nope') };
  ok( $missing->is_not_found, 'a missing path is 404 and stays an API error on this level' );
  my $patch = error_of { $redfish->patch( $system, { AssetTag => 'x' } ) };
  is( $patch->http_status, 405, 'patch sends PATCH' );
  is( $fake->requests->[-1]->content, '{"AssetTag":"x"}', 'with its body' );
  $redfish->get($system);
  is( $redfish->delete('/redfish/v1/Sessions/1'), undef, 'delete sends DELETE' );
  isa_ok( error_of { $redfish->get('redfish/v1') }, 'WWW::iDRAC::Error::Validation', 'a path without a leading slash' );
  isa_ok( error_of { $redfish->get(undef) }, 'WWW::iDRAC::Error::Validation', 'no path' );
};

subtest 'members' => sub {
  my $fake    = FakeiDRAC->new;
  my $redfish = transport($fake);
  my @inline  = $redfish->members( $manager.'/Logs/Sel' );
  is_deeply( [ map { $_->{Id} } @inline ], [ 2, 3, 1 ], 'whole entries are taken as they are, in the order of the controller' );
  is( scalar $fake->seen(qr{Logs/Sel/}), 0, 'without a request per entry' );

  my @paged = $redfish->members( $manager.'/Logs/Lclog' );
  is_deeply( [ map { $_->{Id} } @paged ], [ 3, 2, 1 ], 'addresses are fetched, and the second page followed' );

  my $before  = @{ $fake->requests };
  my @limited = $redfish->members( $manager.'/Logs/Lclog', limit => 2 );
  is( scalar @limited, 2, 'limit caps the entries' );
  is( @{ $fake->requests } - $before, 3, 'and the requests: the collection and two entries' );

  $fake->doc( $manager.'/Logs/Lclog?$skip=2' )->{'Members@odata.nextLink'} = 'https://idrac.test'.$manager.'/Logs/Lclog';
  is( scalar( () = $redfish->members( $manager.'/Logs/Lclog' ) ), 3, 'a next link that leads back ends the walk' );

  $fake->doc( $manager.'/Logs/Sel' )->{Members} = undef;
  is_deeply( [ $redfish->members( $manager.'/Logs/Sel' ) ], [], 'a collection without members' );
  isa_ok( error_of { $redfish->members( $manager.'/Logs/Sel', limit => 0 ) }, 'WWW::iDRAC::Error::Validation', 'limit 0' );
};

subtest 'locate' => sub {
  my $fake    = FakeiDRAC->new;
  my $redfish = transport($fake);
  is( $redfish->locate('Systems'), $system, 'the system, from the collection' );
  is( $redfish->locate('Chassis'), '/redfish/v1/Chassis/System.Embedded.1', 'the chassis the system names, not the first of the collection' );
  is( $redfish->locate('Managers'), $manager, 'the manager the system names' );
  my $before = @{ $fake->requests };
  $redfish->locate($_) for qw( Systems Chassis Managers );
  is( scalar @{ $fake->requests }, $before, 'remembered' );
  isa_ok( error_of { $redfish->locate('Sessions') }, 'WWW::iDRAC::Error::Validation', 'another kind' );

  my $bare = FakeiDRAC->new;
  delete $bare->doc($system)->{Links};
  delete $bare->doc('/redfish/v1')->{Managers};
  my $other = transport($bare);
  is( $other->locate('Chassis'), '/redfish/v1/Chassis/Enclosure.Internal.0-1', 'without links the first of the collection' );
  is( $other->locate('Managers'), undef, 'undef where the controller has none' );
};

subtest 'something that is not Redfish' => sub {
  my $fake = FakeiDRAC->new;
  delete $fake->doc('/redfish/v1')->{RedfishVersion};
  my $error = error_of { transport($fake)->get($system) };
  isa_ok( $error, 'WWW::iDRAC::Error::API' );
  like( "$error", qr/is Redfish enabled on this iDRAC\?/, 'says what to look at' );

  my $silent = FakeiDRAC->new;
  delete $silent->doc('/redfish/v1')->{Links};
  like( error_of { transport($silent)->get($system) }, qr/names no session collection/, 'a service root without a session collection' );
};

done_testing;
```

- [ ] **Step 3: Laufen lassen und scheitern sehen**

Run: `prove -l t/30-redfish.t`
Expected: FAIL, `Can't locate WWW/iDRAC/Redfish.pm in @INC`.

- [ ] **Step 4: Den Transport schreiben**

`lib/WWW/iDRAC/Redfish.pm`:

```perl
package WWW::iDRAC::Redfish;

# ABSTRACT: The Redfish transport of WWW::iDRAC, and the way to what the facade does not cover

use Moo;
use Scalar::Util qw( blessed );
use Types::Standard qw( Bool HashRef InstanceOf Maybe Str );
use WWW::iDRAC::Error::API;
use WWW::iDRAC::Error::Validation;
use namespace::autoclean;

our $VERSION = '0.001';

=synopsis

    my $redfish = $idrac->redfish;

    my $system = $redfish->get('/redfish/v1/Systems/System.Embedded.1');
    my @cpus   = $redfish->members( $system->{Processors}{'@odata.id'} );
    $redfish->post( $target, { ResetType => 'On' } );

=description

Everything L<WWW::iDRAC> does in phase 1 goes through this class. It logs in,
keeps the session token, logs in once more when the controller refuses the
token, and finds the system, the chassis and the manager without assuming
their names.

It is also the documented way out: what the facade does not cover yet is
reachable here, as raw Redfish documents. Nothing is translated on this
level, and a path that does not exist is a
L<WWW::iDRAC::Error::API> with C<is_not_found>.

=cut

has base_url => (
  is       => 'ro',
  isa      => Str,
  required => 1
);

=attr base_url

Required. C<https://host>, without a path.

=cut

has username => ( is => 'ro', isa => Str, required => 1 );
has password => ( is => 'ro', isa => Str, required => 1 );

=attr username

=attr password

Required.

=cut

has session => (
  is      => 'ro',
  isa     => Bool,
  default => 1
);

=attr session

True by default: log in once and send the session token. False sends the
credentials with every request as Basic authentication and creates no
session.

=cut

has ua => (
  is       => 'ro',
  isa      => InstanceOf ['LWP::UserAgent'],
  required => 1
);

=attr ua

Required. The L<LWP::UserAgent> all requests go through.

=cut

has _token        => ( is => 'rw', isa => Maybe [Str] );
has _session_path => ( is => 'rw', isa => Maybe [Str] );
has _root         => ( is => 'rw', isa => Maybe [HashRef] );
has _located      => ( is => 'ro', isa => HashRef, default => sub { {} } );

with 'WWW::iDRAC::Role::HTTP';

sub url {
  my ( $self, $path ) = @_;
  WWW::iDRAC::Error::Validation->throw( message => 'a Redfish path starts with a slash, got '.( $path // 'nothing' ) )
    unless defined $path && !ref $path && $path =~ m{\A/};
  return $self->base_url.$path;
}

=method url

    my $url = $redfish->url('/redfish/v1/');

The address of a path on this controller.

=cut

sub path_of {
  my ( $self, $address ) = @_;
  return undef unless defined $address && !ref $address && length $address;
  $address =~ s{\A[a-z][a-z0-9+.-]*://[^/]+}{}i;
  return $address;
}

=method path_of

    my $path = $redfish->path_of( $result->{location} );

The path of an address the controller handed out. Some firmware gives a full
URL where other firmware gives a path.

=cut

sub root {
  my ( $self ) = @_;
  return $self->_root if $self->_root;
  my $url = $self->url('/redfish/v1/');
  my $result;
  if ( !eval { $result = $self->send_request( GET => $url ); 1 } ) {
    my $error = $@;
    die $error unless blessed $error && $error->isa( $self->api_error_class ) && $error->is_unauthorized;
    # the service root is meant to be readable without a login; a controller
    # that wants one anyway gets the credentials
    $result = $self->send_request( GET => $url, basic => [ $self->username, $self->password ] );
  }
  $self->api_error_class->throw(
    message     => 'GET '.$url.' did not answer with a Redfish service root; is Redfish enabled on this iDRAC?',
    http_status => $result->{status}
  ) unless ref $result->{data} eq 'HASH' && defined $result->{data}{RedfishVersion};
  return $self->_root( $result->{data} );
}

=method root

The service root document. Read once and kept.

=cut

sub login {
  my ( $self ) = @_;
  my $links = $self->root->{Links};
  my $path  = ref $links eq 'HASH' && ref $links->{Sessions} eq 'HASH' ? $links->{Sessions}{'@odata.id'} : undef;
  $self->api_error_class->throw( message => 'the service root of '.$self->base_url.' names no session collection', http_status => 200 )
    unless defined $path;
  my $url    = $self->url($path);
  my $result = $self->send_request( POST => $url, json => { UserName => $self->username, Password => $self->password } );
  $self->api_error_class->throw( message => 'POST '.$url.' answered without an X-Auth-Token', http_status => $result->{status} )
    unless defined $result->{token};
  $self->_token( $result->{token} );
  $self->_session_path( $self->path_of( $result->{location} ) // ( ref $result->{data} eq 'HASH' ? $result->{data}{'@odata.id'} : undef ) );
  return 1;
}

=method login

Creates a session. Called for you by the first request; the session
collection is taken from the service root, because its path differs between
the generations.

=cut

sub forget_session {
  my ( $self ) = @_;
  $self->_token(undef);
  $self->_session_path(undef);
  return;
}

=method forget_session

Drops the token without telling the controller, for when the controller has
dropped the session itself.

=cut

sub logout {
  my ( $self ) = @_;
  my $token = $self->_token;
  my $path  = $self->_session_path;
  $self->forget_session;
  return 0 unless defined $token && defined $path;
  $self->send_request( DELETE => $self->url($path), token => $token );
  return 1;
}

=method logout

Ends the session, if there is one. An iDRAC allows only a few sessions at a
time and frees an abandoned one only after a timeout, so call this when you
are done. The object also does it when it is destroyed.

=cut

sub DEMOLISH {
  my ( $self ) = @_;
  local ( $@, $!, $? );
  eval { $self->logout };
  return;
}

sub request {
  my ( $self, $method, $path, %arg ) = @_;
  my $url = $self->url($path);
  return $self->send_request( $method => $url, %arg, basic => [ $self->username, $self->password ] ) unless $self->session;
  $self->login unless defined $self->_token;
  my $result;
  return $result if eval { $result = $self->send_request( $method => $url, %arg, token => $self->_token ); 1 };
  my $error = $@;
  die $error unless blessed $error && $error->isa( $self->api_error_class ) && $error->is_unauthorized;
  # the session ran out or the controller was restarted: one new login, one more try
  $self->forget_session;
  $self->login;
  return $self->send_request( $method => $url, %arg, token => $self->_token );
}

=method request

    my $result = $redfish->request( PATCH => $path, json => \%body );

One authenticated request. Returns C<status>, C<data>, C<location> and
C<token>, see L<WWW::iDRAC::Role::HTTP/read_response>. A refused token leads
to exactly one new login and one more try.

=cut

sub get    { $_[0]->request( GET => $_[1] )->{data} }
sub post   { $_[0]->request( POST => $_[1], json => $_[2] // {} )->{data} }
sub patch  { $_[0]->request( PATCH => $_[1], json => $_[2] // {} )->{data} }
sub delete { $_[0]->request( DELETE => $_[1] )->{data} }

=method get

    my $doc = $redfish->get($path);

=method post

    my $doc = $redfish->post( $path, \%body );

=method patch

    my $doc = $redfish->patch( $path, \%body );

=method delete

    $redfish->delete($path);

The four verbs. Each returns the decoded document of the answer, or C<undef>
when the answer has no body.

=cut

sub members {
  my ( $self, $path, %arg ) = @_;
  my $limit = $arg{limit};
  WWW::iDRAC::Error::Validation->throw( message => 'limit is a positive number, got '.$limit )
    if defined $limit && $limit !~ /\A[1-9][0-9]*\z/;
  my ( @docs, %seen );
  while ( defined $path && !$seen{$path}++ ) {
    my $collection = $self->get($path);
    last unless ref $collection eq 'HASH';
    for my $member ( ref $collection->{Members} eq 'ARRAY' ? @{ $collection->{Members} } : () ) {
      next unless ref $member eq 'HASH';
      # a member that carries more than its address is already the document
      push @docs, keys %$member > 1 || !defined $member->{'@odata.id'} ? $member : $self->get( $member->{'@odata.id'} );
      return @docs if defined $limit && @docs >= $limit;
    }
    $path = $self->path_of( $collection->{'Members@odata.nextLink'} );
  }
  return @docs;
}

=method members

    my @docs = $redfish->members( $path, limit => 50 );

The entries of a collection as documents, in the order the controller lists
them. Where the controller puts the whole entries into C<Members> they are
taken as they are; where it puts only addresses there, each one is fetched,
because old firmware does not know C<$expand>. Further pages are followed.
C<limit> caps the number of entries and so the number of requests.

=cut

sub locate {
  my ( $self, $kind ) = @_;
  WWW::iDRAC::Error::Validation->throw( message => 'locate knows Systems, Chassis and Managers, got '.( $kind // 'nothing' ) )
    unless defined $kind && $kind =~ /\A(?:Systems|Chassis|Managers)\z/;
  my $located = $self->_located;
  return $located->{$kind} if exists $located->{$kind};
  my $path;
  if ( $kind ne 'Systems' && defined( my $system = $self->locate('Systems') ) ) {
    # the system says which chassis holds it and which manager manages it
    my $doc   = $self->get($system);
    my $links = ref $doc eq 'HASH' ? $doc->{Links} : undef;
    my $list  = ref $links eq 'HASH' ? $links->{ $kind eq 'Chassis' ? 'Chassis' : 'ManagedBy' } : undef;
    ( $path ) = map { $_->{'@odata.id'} } grep { ref $_ eq 'HASH' && defined $_->{'@odata.id'} } ref $list eq 'ARRAY' ? @$list : ();
  }
  if ( !defined $path ) {
    my $collection = $self->root->{$kind};
    if ( ref $collection eq 'HASH' && defined $collection->{'@odata.id'} ) {
      my $doc = $self->get( $collection->{'@odata.id'} );
      ( $path ) = map { $_->{'@odata.id'} } grep { ref $_ eq 'HASH' && defined $_->{'@odata.id'} } ref $doc->{Members} eq 'ARRAY' ? @{ $doc->{Members} } : ();
    }
  }
  return $located->{$kind} = $path;
}

=method locate

    my $path = $redfish->locate('Systems');    # or Chassis, Managers

The path of the system, of the chassis that holds it and of the manager that
manages it, or C<undef> when the controller has none. Found through the
collections of the service root and the links of the system, not through
fixed names, and remembered for the lifetime of the object. Readings and
states are never remembered.

=cut

1;
```

`DEMOLISH` beendet die Session auch beim Programmende und lässt `$@` und `$?` unberührt; im Prototyp nach `exit` und nach `die` geprüft.

- [ ] **Step 5: `t/00-load.t` ergänzen**

`t/00-load.t`:

```perl
#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

for (qw(
  WWW::iDRAC
  WWW::iDRAC::Error
  WWW::iDRAC::Error::API
  WWW::iDRAC::Error::Network
  WWW::iDRAC::Error::Unsupported
  WWW::iDRAC::Error::Validation
  WWW::iDRAC::Redfish
  WWW::iDRAC::Role::HTTP
)) {
  use_ok($_);
}

done_testing;
```

- [ ] **Step 6: Laufen lassen**

Run: `prove -lr t`
Expected: PASS, 4 Dateien.

- [ ] **Step 7: Übergabe**

Vorschlag: `Add the Redfish transport and the fake controller for the unit tests`.

---

### Task 4: Bereinigung und Recorder

**Files:**
- Create: `t/lib/iDRACSanitize.pm`, `t/lib/iDRACRecorder.pm`, `t/idrac/record.pl`
- Test: `t/35-sanitize.t`, `t/36-recorder.t`

**Interfaces:**
- Consumes: `WWW::iDRAC::Redfish` (`get`, `root`, `logout`), `FakeiDRAC` (Aufgabe 3).
- Produces: `iDRACSanitize->new->hide( $kind => $value )->sanitize( \%docs )` → bereinigte Kopie der Abbildung Pfad → Dokument; `iDRACSanitize->leaks( \%docs, @values )` → die Werte, die noch darin stehen.
- Produces: `iDRACRecorder->new( redfish => $redfish, max_docs => 500, max_members => 20 )->record` → Abbildung Pfad → Dokument; `->skipped`, `->failed`.
- Produces: `t/idrac/record.pl <name>` schreibt `t/fixtures/<name>/redfish.json` und druckt, was Spec-Abschnitt 9 wissen will.

- [ ] **Step 1: Die Tests schreiben**

`t/35-sanitize.t`:

```perl
#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';

use iDRACSanitize;

my $system = '/redfish/v1/Systems/System.Embedded.1';

my %docs = (
  $system => {
    '@odata.id'   => $system,
    '@odata.type' => '#ComputerSystem.v1_0_2.ComputerSystem',
    SKU           => 'ABC1234',
    SerialNumber  => 'CN701636AB0013',
    UUID          => '4c4c4544-0042-4310-8031-c2c04f313233',
    AssetTag      => '',
    HostName      => 'pichu',
    BiosVersion   => '2.4.3',
    Model         => 'PowerEdge T330',
    Actions       => { '#ComputerSystem.Reset' => { target => $system.'/Actions/ComputerSystem.Reset' } }
  },
  '/redfish/v1/Managers/iDRAC.Embedded.1' => {
    FirmwareVersion => '2.83.83.83',
    Oem             => { Dell => { ServiceTag => 'ABC1234', DNSRacName => 'ab', Note => 'Service tag ABC1234 belongs to pichu.lan.example.net', Slot => 'cable ab' } }
  },
  '/redfish/v1/Managers/iDRAC.Embedded.1/EthernetInterfaces/NIC.1' => {
    FQDN                => 'idrac-ABC1234.lan.example.net',
    MACAddress          => '18:66:da:aa:bb:cc',
    PermanentMACAddress => '18:66:DA:AA:BB:CC',
    IPv4Addresses       => [ { Address => '10.20.30.40', SubnetMask => '255.255.255.0', Gateway => '10.20.30.1' } ],
    IPv6Addresses       => [ { Address => 'fe80::1a66:daff:feaa:bbcc' }, { Address => '::' } ],
    NameServers         => [ '10.20.30.1', '0.0.0.0' ]
  },
  '/redfish/v1/Managers/iDRAC.Embedded.1/Logs/Sel' => {
    Members => [ { Id => '1', Created => '2026-10-01T12:30:45+02:00', Message => 'Login of root from 10.20.30.99 at 12:30:45, then from fe80::99. Firmware 2.83.83.83.' } ]
  }
);

my $sanitizer = iDRACSanitize->new->hide( host => 'idrac-t330.lan' )->hide( user => 'root' );
my $clean     = $sanitizer->sanitize( \%docs );
my $sys       = $clean->{$system};
my $nic       = $clean->{'/redfish/v1/Managers/iDRAC.Embedded.1/EthernetInterfaces/NIC.1'};
my $manager   = $clean->{'/redfish/v1/Managers/iDRAC.Embedded.1'};
my $entry     = $clean->{'/redfish/v1/Managers/iDRAC.Embedded.1/Logs/Sel'}{Members}[0];

subtest 'identifying values by their key' => sub {
  is( $sys->{SKU}, 'TAG0001', 'the service tag' );
  is( $sys->{SerialNumber}, 'SERIAL0001', 'the serial number' );
  is( $sys->{UUID}, '00000000-0000-0000-0000-000000000001', 'the UUID, still in the form of one' );
  is( $sys->{HostName}, 'host-3', 'a host name' );
  is( $manager->{Oem}{Dell}{DNSRacName}, 'host-2', 'however short' );
  is( $sys->{AssetTag}, '', 'an empty value stays empty' );
  is( $manager->{Oem}{Dell}{ServiceTag}, 'TAG0001', 'the same value gets the same placeholder everywhere' );
};

subtest 'the same values inside other strings' => sub {
  is( $manager->{Oem}{Dell}{Note}, 'Service tag TAG0001 belongs to host-3.example-1.org', 'the tag, the name and the domain inside a sentence' );
  is( $manager->{Oem}{Dell}{Slot}, 'cable ab', 'a value of fewer than four characters is not searched for inside other strings' );
  is( $nic->{FQDN}, 'fqdn-1.example.org', 'a value that is replaced as a whole' );
};

subtest 'addresses' => sub {
  is( $nic->{MACAddress}, '00:00:5E:00:53:01', 'a MAC address' );
  is( $nic->{PermanentMACAddress}, '00:00:5E:00:53:01', 'the same one in other case' );
  is_deeply( $nic->{IPv4Addresses}, [ { Address => '192.0.2.1', SubnetMask => '255.255.255.0', Gateway => '192.0.2.2' } ], 'IPv4 addresses, the netmask kept' );
  is_deeply( $nic->{IPv6Addresses}, [ { Address => '2001:db8::1' }, { Address => '::' } ], 'an IPv6 address, the unset one kept' );
  is_deeply( $nic->{NameServers}, [ '192.0.2.2', '0.0.0.0' ], 'the same address the same placeholder, the unset one kept' );
  is( $entry->{Message}, 'Login of user-1 from 192.0.2.3 at 12:30:45, then from 2001:db8::2. Firmware 192.0.2.4.', 'inside a sentence and at the end of one, the user name with it; a time is no IPv6 address' );
  is( $entry->{Created}, '2026-10-01T12:30:45+02:00', 'a timestamp is left alone' );
};

subtest 'what must stay as it is' => sub {
  is( $manager->{FirmwareVersion}, '2.83.83.83', 'a firmware version under its own key is no IPv4 address' );
  is( $sys->{BiosVersion}, '2.4.3', 'the BIOS version' );
  is( $sys->{Model}, 'PowerEdge T330', 'the model' );
  is( $sys->{'@odata.id'}, $system, 'addresses of documents' );
  is( $sys->{'@odata.type'}, '#ComputerSystem.v1_0_2.ComputerSystem', 'types' );
  is( $sys->{Actions}{'#ComputerSystem.Reset'}{target}, $system.'/Actions/ComputerSystem.Reset', 'action targets' );
  is_deeply( [ sort keys %$clean ], [ sort keys %docs ], 'the paths' );
  is( $docs{$system}{SKU}, 'ABC1234', 'the input is not changed' );
};

subtest 'leaks' => sub {
  my @secret = ( 'ABC1234', 'CN701636AB0013', '10.20.30.40', '18:66:da:aa:bb:cc', 'fe80::1a66:daff:feaa:bbcc', 'lan.example.net', 'pichu', 'idrac-t330.lan' );
  is_deeply( [ iDRACSanitize->leaks( $clean, @secret ) ], [], 'none of the identifying values is left' );
  is_deeply( [ iDRACSanitize->leaks( \%docs, @secret, undef, '' ) ], [ sort @secret[ 0 .. 6 ] ], 'and leaks finds them where they are' );
};

done_testing;
```

`t/36-recorder.t`:

```perl
#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';

use FakeiDRAC;
use iDRACRecorder;
use WWW::iDRAC::Redfish;

my $manager = '/redfish/v1/Managers/iDRAC.Embedded.1';

sub recorder {
  my ( $fake, %arg ) = @_;
  my $redfish = WWW::iDRAC::Redfish->new( base_url => 'https://'.$fake->host, username => 'root', password => 'calvin', ua => $fake );
  return iDRACRecorder->new( redfish => $redfish, %arg );
}

subtest 'the whole tree, with GET only' => sub {
  my $fake = FakeiDRAC->new;
  my $docs = recorder($fake)->record;
  is_deeply( [ sort keys %$docs ], [ sort keys %{ FakeiDRAC->default_docs } ], 'every document the controller has, under the path the fake serves it at' );
  is_deeply( [ $fake->seen(qr/\A(?!GET )/) ], [ 'POST /redfish/v1/Sessions', 'DELETE /redfish/v1/Sessions/1' ], 'nothing but GET, apart from the login and the logout' );
  is( $docs->{$manager}{FirmwareVersion}, '2.83.83.83', 'the documents as they came' );
};

subtest 'a recording can be served again' => sub {
  my $docs  = recorder( FakeiDRAC->new )->record;
  my $again = recorder( FakeiDRAC->new( docs => $docs ) )->record;
  is_deeply( $again, $docs, 'the same recording from the recording' );
};

subtest 'what is not walked' => sub {
  my $fake = FakeiDRAC->new;
  $fake->doc('/redfish/v1')->{AccountService} = { '@odata.id' => '/redfish/v1/Managers/iDRAC.Embedded.1/AccountService' };
  $fake->doc('/redfish/v1')->{JsonSchemas}    = { '@odata.id' => '/redfish/v1/JSONSchemas' };
  $fake->doc($manager)->{Links}               = { Gone => { '@odata.id' => $manager.'/Gone#/Part' }, Elsewhere => { '@odata.id' => 'https://other.test/x' } };
  my $recorder = recorder($fake);
  my $docs     = $recorder->record;
  is_deeply( [ sort @{ $recorder->skipped } ], [ '/redfish/v1/JSONSchemas', '/redfish/v1/Managers/iDRAC.Embedded.1/AccountService', '/redfish/v1/Sessions' ], 'accounts, sessions and schemas are left out' );
  is( scalar $fake->seen(qr/AccountService|JSONSchemas/), 0, 'and not even asked for' );
  is_deeply( [ keys %{ $recorder->failed } ], [ $manager.'/Gone' ], 'a link that leads nowhere is noted, without its fragment, and the walk goes on' );
  ok( exists $docs->{ $manager.'/Logs/Lclog/1' }, 'to the end' );
};

subtest 'limits' => sub {
  my $fake = FakeiDRAC->new;
  $fake->doc( $manager.'/Logs/Sel' )->{Members} = [ map { { '@odata.id' => $manager.'/Logs/Sel/'.$_, Id => "$_" } } 1 .. 30 ];
  my $docs = recorder( $fake, max_members => 5 )->record;
  my $sel  = $docs->{ $manager.'/Logs/Sel' };
  is( scalar @{ $sel->{Members} }, 5, 'a long collection is cut' );
  is( $sel->{'Members@odata.count'}, 5, 'and its count says so' );
  my $log = recorder( FakeiDRAC->new, max_members => 1 )->record->{ $manager.'/Logs/Lclog' };
  ok( !exists $log->{'Members@odata.nextLink'}, 'a cut collection has no next page' );
  is( scalar keys %{ recorder( FakeiDRAC->new, max_docs => 4 )->record }, 4, 'the number of documents is capped' );
};

done_testing;
```

- [ ] **Step 2: Laufen lassen und scheitern sehen**

Run: `prove -l t/35-sanitize.t t/36-recorder.t`
Expected: FAIL, `Can't locate iDRACSanitize.pm in @INC` und `Can't locate iDRACRecorder.pm`.

- [ ] **Step 3: Die Bereinigung schreiben**

`t/lib/iDRACSanitize.pm`. Zwei Fallen, die der Prototyp gefunden hat und die niemand „vereinfachen“ darf: Eine Firmware-Version hat die Form einer IPv4-Adresse und bleibt unter ihrem eigenen Schlüssel unangetastet; und eine Adresse am Satzende, gefolgt von einem Punkt, muss trotzdem erkannt werden.

```perl
package iDRACSanitize;

# Takes what identifies a machine or a network out of recorded Redfish
# documents, before they are written to t/fixtures/. The repository is
# public; a recording that was not through here is not committed.
#
#   my $clean = iDRACSanitize->new->hide( host => 'idrac.lan' )->sanitize( \%docs );
#
# Three passes over the documents, which are a map of path to document:
#
#   1. the values of the keys in %BY_KEY are collected, each gets a
#      placeholder, and the same value gets the same placeholder everywhere
#   2. every string is rewritten: a collected value becomes its placeholder,
#      MAC and IP addresses become addresses from the documentation ranges
#   3. leaks() looks for values that must not be in the result
#
# Structural strings are left alone: keys, @odata values and action targets.

use strict;
use warnings;
use Socket qw( AF_INET6 inet_pton );

# key => the kind of placeholder its value gets
my %BY_KEY = (
  SerialNumber          => 'serial',
  SKU                   => 'tag',
  ServiceTag            => 'tag',
  ChassisServiceTag     => 'tag',
  NodeID                => 'tag',
  ExpressServiceCode    => 'code',
  AssetTag              => 'asset',
  UUID                  => 'uuid',
  ServiceEntryPointUUID => 'uuid',
  HostName              => 'host',
  FQDN                  => 'fqdn',
  DNSRacName            => 'host',
  DNSDomainName         => 'domain',
  UserName              => 'user'
);

my %FORMAT = (
  serial => sub { sprintf 'SERIAL%04d', $_[0] },
  tag    => sub { sprintf 'TAG%04d', $_[0] },
  code   => sub { sprintf '%011d', $_[0] },
  asset  => sub { sprintf 'ASSET%04d', $_[0] },
  uuid   => sub { sprintf '00000000-0000-0000-0000-%012d', $_[0] },
  host   => sub { sprintf 'host-%d', $_[0] },
  fqdn   => sub { sprintf 'fqdn-%d.example.org', $_[0] },
  domain => sub { sprintf 'example-%d.org', $_[0] },
  user   => sub { sprintf 'user-%d', $_[0] },
  mac    => sub { sprintf '00:00:5E:00:53:%02X', $_[0] % 256 },
  ipv4   => sub { sprintf '192.0.2.%d', $_[0] % 256 },
  ipv6   => sub { sprintf '2001:db8::%x', $_[0] }
);

sub new { bless { map => {}, count => {} }, $_[0] }

# the placeholder of a value, the same one each time
sub placeholder {
  my ( $self, $kind, $value ) = @_;
  return $self->{map}{$value} //= $FORMAT{$kind}->( ++$self->{count}{$kind} );
}

# a value known from outside the documents, the address the recording was made at for example
sub hide {
  my ( $self, $kind, $value ) = @_;
  $self->placeholder( $kind, $value ) if defined $value && length $value;
  return $self;
}

sub _walk {
  my ( $self, $node, $key, $visit ) = @_;
  # in the order of the keys, so that the same recording gets the same placeholders each time
  if ( ref $node eq 'HASH' ) { return { map { $_ => $self->_walk( $node->{$_}, $_, $visit ) } sort keys %$node } }
  if ( ref $node eq 'ARRAY' ) { return [ map { $self->_walk( $_, $key, $visit ) } @$node ] }
  return $node if ref $node || !defined $node;
  return $visit->( $node, $key );
}

sub _structural { $_[0] =~ /\A\@odata\.|\@odata\.|\Atarget\z/ }

sub _addresses {
  my ( $self, $text, $key ) = @_;
  $text =~ s{\b((?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2})\b}{ $self->placeholder( mac => uc $1 ) }ge;
  # a firmware version has the form of an IPv4 address
  $text =~ s{(?<![0-9.])((?:[0-9]{1,3}\.){3}[0-9]{1,3})(?![0-9]|\.[0-9])}{ $self->_ipv4($1) }ge unless $key =~ /version|firmware/i;
  $text =~ s{(?<![0-9A-Za-z:])([0-9A-Fa-f:]{2,39})(?![0-9A-Za-z:])}{ $self->_ipv6($1) }ge;
  return $text;
}

sub _ipv4 {
  my ( $self, $address ) = @_;
  return $address if grep { $_ > 255 } split /\./, $address;
  # not set, a netmask, the machine itself, already a documentation address
  return $address if $address =~ /\A(?:0\.0\.0\.0|255\.|127\.|192\.0\.2\.)/;
  return $self->placeholder( ipv4 => $address );
}

sub _ipv6 {
  my ( $self, $address ) = @_;
  return $address unless $address =~ /:.*:/ && defined inet_pton( AF_INET6, $address );
  return $address if $address =~ /\A(?:::1?|2001:db8:.*)\z/i;
  return $self->placeholder( ipv6 => lc $address );
}

sub sanitize {
  my ( $self, $docs ) = @_;
  $self->_walk( $docs, '', sub {
    my ( $value, $key ) = @_;
    my $kind = $BY_KEY{$key};
    return $value unless $kind && length $value;
    $self->placeholder( $kind, $value );
    # the domain of a full name is in other strings without the name in front
    $self->placeholder( domain => $1 ) if $kind eq 'fqdn' && $value =~ /\A[^.]+\.(.+\..+)\z/;
    return $value;
  } );
  # longest first, so that a value inside another does not break it up
  my @known = sort { length $b <=> length $a || $a cmp $b } grep { length >= 4 } keys %{ $self->{map} };
  my $known = @known ? join '|', map { quotemeta } @known : undef;
  return $self->_walk( $docs, '', sub {
    my ( $value, $key ) = @_;
    return $value if _structural($key);
    return $self->{map}{$value} if exists $self->{map}{$value};
    $value =~ s/($known)/$self->{map}{$1}/g if defined $known;
    return $self->_addresses( $value, $key );
  } );
}

# the values out of @values that are still in the documents
sub leaks {
  my ( $class, $docs, @values ) = @_;
  my %found;
  $class->_walk( $docs, '', sub {
    my ( $value ) = @_;
    $found{$_} = 1 for grep { defined && length && index( $value, $_ ) >= 0 } @values;
    return $value;
  } );
  return sort keys %found;
}

1;
```

- [ ] **Step 4: Den Recorder schreiben**

`t/lib/iDRACRecorder.pm`:

```perl
package iDRACRecorder;

# Walks the Redfish tree of a controller with GET requests only and returns
# what it found as a map of path to document, the form FakeiDRAC serves.
#
#   my $docs = iDRACRecorder->new( redfish => $redfish )->record;

use strict;
use warnings;

# what is not walked: the schema and message catalogues, which are large and
# say nothing about this controller, and everything about accounts, sessions
# and certificates
my $SKIP = qr{/(?:JSONSchemas|JsonSchemas|Registries|\$metadata|odata|AccountService|SessionService|Sessions|CertificateService|Certificates|Subscriptions)(?:/|\z)};

sub new {
  my ( $class, %arg ) = @_;
  return bless {
    redfish     => $arg{redfish},
    max_docs    => $arg{max_docs}    // 500,
    max_members => $arg{max_members} // 20,
    skipped     => [],
    failed      => {}
  }, $class;
}

sub skipped { $_[0]{skipped} }
sub failed  { $_[0]{failed} }

sub key {
  my ( $class, $path ) = @_;
  $path =~ s/#.*\z//;
  $path =~ s{/+\z}{} unless $path eq '/';
  return $path;
}

# every address a document points to
sub links {
  my ( $class, $node ) = @_;
  return map { $class->links($_) } @$node if ref $node eq 'ARRAY';
  return () unless ref $node eq 'HASH';
  return map {
    my $value = $node->{$_};
    ref $value ? $class->links($value)
      : ( $_ eq '@odata.id' || $_ eq 'Members@odata.nextLink' ) && defined $value && $value =~ m{\A/redfish/v1(?:/|\z)} ? $value
      :                                                                                                                 ()
  } sort keys %$node;
}

# a long collection is cut to its first entries, and says so
sub trim {
  my ( $self, $doc ) = @_;
  my $members = $doc->{Members};
  return $doc unless ref $members eq 'ARRAY' && @$members > $self->{max_members};
  my %cut = ( %$doc, Members => [ @$members[ 0 .. $self->{max_members} - 1 ] ], 'Members@odata.count' => $self->{max_members} );
  delete $cut{'Members@odata.nextLink'};
  return \%cut;
}

sub record {
  my ( $self ) = @_;
  my ( %docs, %seen );
  my @queue = ('/redfish/v1/');
  while ( @queue && keys %docs < $self->{max_docs} ) {
    my $key = $self->key( shift @queue );
    next if $seen{$key}++;
    if ( $key =~ $SKIP ) { push @{ $self->{skipped} }, $key; next }
    my $doc;
    if ( !eval { $doc = $self->{redfish}->get($key); 1 } ) { $self->{failed}{$key} = "$@"; next }
    next unless ref $doc eq 'HASH';
    $docs{$key} = $self->trim($doc);
    # an entry that came whole inside its collection is not fetched once more
    $seen{ $self->key( $_->{'@odata.id'} ) }++
      for grep { ref $_ eq 'HASH' && keys %$_ > 1 && defined $_->{'@odata.id'} } ref $docs{$key}{Members} eq 'ARRAY' ? @{ $docs{$key}{Members} } : ();
    push @queue, $self->links( $docs{$key} );
  }
  return \%docs;
}

1;
```

`t/idrac/record.pl`:

```perl
#!/usr/bin/env perl

# Records what one iDRAC answers over Redfish into t/fixtures/<name>/redfish.json,
# cleaned of what identifies the machine and its network, and prints what the
# design wants to know about the controller.
#
#   IDRAC_HOST=192.0.2.10 IDRAC_USERNAME=root IDRAC_PASSWORD=... \
#   IDRAC_SSL_FINGERPRINT='sha256$...' \
#     perl -Ilib -It/lib t/idrac/record.pl idrac8
#
# IDRAC_VERIFY_SSL=0 instead of the fingerprint accepts any certificate.
# The script only sends GET requests, apart from the login and the logout.

use strict;
use warnings;
use File::Path qw( make_path );
use JSON::MaybeXS;
use LWP::UserAgent;
use iDRACRecorder;
use iDRACSanitize;
use WWW::iDRAC::Redfish;

my $name = shift // '';
die "usage: $0 <name>, for example idrac7 or idrac8\n" unless $name =~ /\A[a-z0-9][a-z0-9-]*\z/;
defined $ENV{$_} && length $ENV{$_} or die "set $_\n" for qw( IDRAC_HOST IDRAC_USERNAME IDRAC_PASSWORD );

my %ssl = ( $ENV{IDRAC_VERIFY_SSL} // 1 ) ? ( verify_hostname => 1 ) : ( verify_hostname => 0, SSL_verify_mode => 0 );
$ssl{SSL_fingerprint} = $ENV{IDRAC_SSL_FINGERPRINT} if $ENV{IDRAC_SSL_FINGERPRINT};
my $ua      = LWP::UserAgent->new( timeout => 60, keep_alive => 1, ssl_opts => \%ssl );
my $base    = 'https://'.$ENV{IDRAC_HOST};
my $redfish = WWW::iDRAC::Redfish->new( base_url => $base, username => $ENV{IDRAC_USERNAME}, password => $ENV{IDRAC_PASSWORD}, ua => $ua );

my $hello = $ua->get( $base.'/redfish/v1/' );
my $root  = $redfish->root;

my $recorder = iDRACRecorder->new( redfish => $redfish );
my $raw      = $recorder->record;
my $sessions = eval { $redfish->get('/redfish/v1/SessionService') } || {};
my $open     = eval { $redfish->get( $root->{Links}{Sessions}{'@odata.id'} ) } || {};
$redfish->logout;

my ( $host ) = $ENV{IDRAC_HOST} =~ /\A\[?([^\]]+?)\]?(?::[0-9]+)?\z/;
my $clean = iDRACSanitize->new->hide( host => $host )->hide( user => $ENV{IDRAC_USERNAME} )->sanitize($raw);
my @leaks = iDRACSanitize->leaks( $clean, $host, $ENV{IDRAC_PASSWORD}, ( map { $_->{SKU}, $_->{SerialNumber} } grep { ref $_ eq 'HASH' } values %$raw ) );
die 'not written, these values are still in the recording: '.join( ', ', @leaks )."\n" if @leaks;

my $dir = 't/fixtures/'.$name;
make_path($dir);
open my $out, '>:raw', $dir.'/redfish.json' or die "cannot write $dir/redfish.json: $!\n";
print {$out} JSON::MaybeXS->new( utf8 => 1, canonical => 1, pretty => 1 )->encode($clean);
close $out or die "cannot write $dir/redfish.json: $!\n";

my ( $system )  = grep { ref $_ eq 'HASH' && $_->{Actions} && $_->{Actions}{'#ComputerSystem.Reset'} } values %$raw;
my ( $manager ) = grep { ref $_ eq 'HASH' && defined $_->{FirmwareVersion} && $_->{Actions} && $_->{Actions}{'#Manager.Reset'} } values %$raw;
my $say = sub { printf "%-22s %s\n", $_[0].':', defined $_[1] && length $_[1] ? $_[1] : '(not reported)' };
$say->( 'fixture', $dir.'/redfish.json, '.keys(%$clean).' documents' );
$say->( 'TLS', join ' ', grep { defined } $hello->header('Client-SSL-Version'), $hello->header('Client-SSL-Cipher') );
$say->( 'Redfish version', $root->{RedfishVersion} );
$say->( 'server model', $system && $system->{Model} );
$say->( 'manager model', $manager && $manager->{Model} );
$say->( 'firmware', $manager && $manager->{FirmwareVersion} );
$say->( 'reset types', $system && join ' ', @{ $system->{Actions}{'#ComputerSystem.Reset'}{'ResetType@Redfish.AllowableValues'} || [] } );
$say->( 'session collection', $root->{Links}{Sessions}{'@odata.id'} );
$say->( 'session timeout', $sessions->{SessionTimeout} );
$say->( 'sessions open', $open->{'Members@odata.count'} );
$say->( 'log services', join ' ', sort grep { m{/LogServices/[^/]+\z} } keys %$raw );
$say->( 'license documents', join ' ', sort grep { /licen[sc]e/i } keys %$raw );
$say->( 'not walked', scalar( @{ $recorder->skipped } ).' paths' );
$say->( 'failed', join ' ', map { $_.' ('.( $recorder->failed->{$_} =~ /failed: ([0-9]{3})/ ? $1 : 'error' ).')' } sort keys %{ $recorder->failed } );
print "\nRead $dir/redfish.json before it is committed: it must not name your machine, your network or a person.\n";
```

- [ ] **Step 5: Laufen lassen**

Run: `prove -lr t && perl -Ilib -It/lib -c t/idrac/record.pl`
Expected: PASS, 6 Dateien; `t/idrac/record.pl syntax OK`.

- [ ] **Step 6: Übergabe**

Vorschlag: `Add the recorder for fixtures and the sanitizer they go through`.

---

### Task 5: Am Gerät — beide iDRACs aufnehmen (Karte 1)

Der einzige Schritt dieses Plans, der echte Hardware berührt, und er liest nur. Er braucht Getty.

**Files:**
- Create: `t/fixtures/idrac8/redfish.json` (PowerEdge T330), `t/fixtures/idrac7/redfish.json` (PowerEdge R720xd)
- Modify: `docs/superpowers/specs/2026-10-04-www-idrac-design.md` (Abschnitt 9)

**Interfaces:**
- Consumes: `t/idrac/record.pl` (Aufgabe 4).
- Produces: zwei Aufnahmen, die `FakeiDRAC->from_file` ausliefert, und die Antworten auf Spec-Abschnitt 9.

- [ ] **Step 1: Zugang von Getty**

Getty nennt die beiden Adressen und legt je Gerät eine Datei an, die nur er lesen kann. Zugangsdaten stehen nie im Chat, in einem Befehl oder im Repo.

```bash
mkdir -p ~/.config/idrac && chmod 700 ~/.config/idrac
cat > ~/.config/idrac/t330.env <<'ENV'
IDRAC_HOST='<Adresse des iDRAC im T330>'
IDRAC_USERNAME='<Benutzer>'
IDRAC_PASSWORD='<Passwort>'
ENV
chmod 600 ~/.config/idrac/t330.env      # dasselbe für r720xd.env
```

- [ ] **Step 2: Erreichbarkeit, TLS und Redfish prüfen**

Für jedes Gerät (`t330`, `r720xd`):

```bash
set -a; . ~/.config/idrac/t330.env; set +a
openssl s_client -connect "$IDRAC_HOST:443" </dev/null 2>/dev/null | grep -E '^ *(Protocol|Cipher) *:'
curl -sk -o /dev/null -w '%{http_code}\n' "https://$IDRAC_HOST/redfish/v1/"
```

Expected: eine Protokollzeile mit `TLSv1.2` oder neuer und HTTP `200`.

Halt und Meldung an Getty, ohne weiterzumachen, wenn:
- `openssl` keine Verbindung bekommt oder nur `TLSv1`/`TLSv1.1` anbietet: Der Controller braucht neuere Firmware. Die Dist bekommt keinen unsicheren Standard.
- `curl` `404` meldet: Die Firmware kennt kein Redfish. Auch hier ist das Firmware-Update Voraussetzung und Handarbeit.

- [ ] **Step 3: Fingerprint holen**

```bash
FP=$(openssl s_client -connect "$IDRAC_HOST:443" </dev/null 2>/dev/null | openssl x509 -noout -fingerprint -sha256 | sed 's/.*=//; s/://g' | tr A-F a-f)
echo "IDRAC_SSL_FINGERPRINT='sha256\$$FP'" >> ~/.config/idrac/t330.env
```

Die Werte stehen in einfachen Anführungszeichen, hier wie in Step 1: Die Datei wird mit `.` eingelesen, und ohne sie frisst die Shell das `$` des Fingerprints und jedes Sonderzeichen im Passwort.

- [ ] **Step 4: Aufnehmen**

```bash
cd ~/dev/p5-www-idrac
( set -a; . ~/.config/idrac/t330.env;   set +a; perl -Ilib -It/lib t/idrac/record.pl idrac8 ) | tee /tmp/idrac8-summary.txt
( set -a; . ~/.config/idrac/r720xd.env; set +a; perl -Ilib -It/lib t/idrac/record.pl idrac7 ) | tee /tmp/idrac7-summary.txt
```

Expected: je eine Zusammenfassung mit Zeilen für `fixture`, `TLS`, `Redfish version`, `server model`, `manager model`, `firmware`, `reset types`, `session collection`, `session timeout`, `sessions open`, `log services`, `license documents`, `not walked`, `failed`. Der Lauf dauert auf einem alten iDRAC einige Minuten.

Bricht der Lauf mit einem Verbindungsfehler mitten im Baum ab, liegt es möglicherweise an Keep-Alive. Dann in `t/idrac/record.pl` `keep_alive => 1` entfernen, noch einmal aufnehmen und den Befund in Spec-Abschnitt 9 festhalten; in dem Fall entfällt `keep_alive` auch in `WWW::iDRAC::_build_ua` (Aufgabe 6).

- [ ] **Step 5: Die Aufnahmen lassen sich ausliefern**

```bash
for n in idrac7 idrac8; do perl -Ilib -It/lib -MFakeiDRAC -MWWW::iDRAC::Redfish -e '
  my $fake = FakeiDRAC->from_file("t/fixtures/$ARGV[0]/redfish.json");
  my $r = WWW::iDRAC::Redfish->new( base_url => "https://".$fake->host, username => "root", password => "calvin", ua => $fake );
  printf "%s: %s\n", $_, $r->locate($_) // "(none)" for qw( Systems Chassis Managers );
' $n; done
```

Expected: für beide je drei Pfade.

- [ ] **Step 6: Getty liest die Aufnahmen**

Die beiden Dateien `t/fixtures/idrac*/redfish.json` gehen an Getty zur Durchsicht, mit dieser Prüfung als Hilfe:

```bash
grep -n -iE 'cihq|\.lan|\.local|192\.168\.|10\.[0-9]+\.[0-9]+\.[0-9]+|172\.(1[6-9]|2[0-9]|3[01])\.' t/fixtures/idrac*/redfish.json | head -40
```

Expected: keine Treffer. Erst mit Gettys Ja gehen die Dateien in die Übergabe. Findet sich etwas, wird der Schlüssel oder das Muster in `t/lib/iDRACSanitize.pm` ergänzt, mit einem Test in `t/35-sanitize.t`, und neu aufgenommen.

- [ ] **Step 7: Spec-Abschnitt 9 beantworten**

Die Tabelle in Abschnitt 9 bekommt eine dritte Spalte „Gemessen (T330 / R720xd)“. Woher jede Antwort kommt:

| Frage in Abschnitt 9 | Quelle |
|---|---|
| Firmware-Stand; Redfish vorhanden? | Zeilen `firmware`, `Redfish version`, `manager model` |
| TLS-Versionen und Cipher | Zeile `TLS` und die Ausgabe von `openssl` aus Step 2 |
| Lizenzstufe über Redfish lesbar? | Zeile `license documents`; leer heißt nein |
| Wie viele Sessions, wie lange? | Zeilen `session timeout`, `sessions open`, `session collection` |
| Wo liegen SEL und Lifecycle-Log, inline oder einzeln? | Zeile `log services`; in der Aufnahme das Dokument, auf das `Entries` zeigt: haben seine `Members` mehr als `@odata.id`, sind sie inline |
| Welche Schlüssel liefert iDRAC 7/8 tatsächlich? | beantwortet Aufgabe 12 mit `t/85-fixtures.t`; hier nur die Zeile `reset types` eintragen |
| WS-Man oder racadm? | bleibt offen bis Phase 2; hier notieren, was die Zeile `failed` und die fehlenden Ressourcen über die Lücken sagen |

- [ ] **Step 8: Folgekarten**

Je Befund eine Notiz auf Karte 1; der Hauptagent legt daraus Karten an:
- `license documents` nicht leer → Karte „Read the license level over Redfish“ (Backlog).
- `reset types` ohne `GracefulShutdown` → Notiz: `power->off` ist auf diesem Controller `Unsupported`; ob `PushPowerButton` als Ersatz dienen soll, entscheidet Getty.
- Modell des Managers nicht in der Form `13G …`/`12G …` → Notiz für Aufgabe 11: `generation_from` erkennt diesen Controller nicht.

- [ ] **Step 9: Übergabe**

Vorschlag: `Record iDRAC 7 and 8, and write down what they answered`. Die Dateien unter `~/.config/idrac/` und `/tmp/idrac*-summary.txt` gehören nicht ins Repo.

---

### Task 6: Util, Fähigkeits-Rolle, System und die Fassade

**Files:**
- Create: `lib/WWW/iDRAC/Util.pm`, `lib/WWW/iDRAC/Role/Capability.pm`, `lib/WWW/iDRAC/System.pm`
- Modify: `lib/WWW/iDRAC.pm` (ganz ersetzen)
- Create: `t/lib/iDRACShapes.pm`
- Test: `t/15-util.t`, `t/40-facade.t`, `t/50-system.t`
- Modify: `t/00-load.t`

**Interfaces:**
- Consumes: `WWW::iDRAC::Redfish` (`get`, `members`, `locate`, `logout`), `WWW::iDRAC::Error::*`, `FakeiDRAC`.
- Produces: `WWW::iDRAC::Util` exportiert auf Wunsch `text($v)`, `number($v)`, `health_of($status)`, `state_of($v)`, `list_of($v)`.
- Produces: Rolle `WWW::iDRAC::Role::Capability`, verlangt `area`; Attribut `redfish` (Pflicht); `unsupported( $method, $reason )` wirft; `fetch( $path, $method )`; `fetch_members( $path, $method, limit => $n )`; `resource( $kind, $method )` → Dokument von System, Chassis oder Manager; `linked_path( $doc, $key, $method )` → Pfad; `supports($method)` → 1/0 über `probe_<method>`.
- Produces: `WWW::iDRAC::System` mit `info`, `processors`, `memory`, `nics` und den reinen Funktionen `info_from`, `processor_from`, `memory_from`, `nic_from`.
- Produces: `WWW::iDRAC->new( host =>, username =>, password =>, session => 1, verify_ssl => 1, ssl_ca_file =>, ssl_fingerprint =>, ssl_opts => {}, timeout => 60, ua => )` mit `base_url`, `ua`, `redfish`, `system`, `logout`.
- Produces: `iDRACShapes` exportiert `shape_ok( $got, 'area.method' )` und `read_methods()`.

- [ ] **Step 1: Die Schlüssel-Tabelle und die Tests schreiben**

`t/lib/iDRACShapes.pm` enthält schon die Schlüssel aller Fähigkeiten; die späteren Aufgaben benutzen sie.

```perl
package iDRACShapes;

# The keys every public reading method of WWW::iDRAC returns, in one place
# for the unit tests, the fixture test and the live suite.
#
#   shape_ok( $idrac->system->info, 'system.info' );

use strict;
use warnings;
use Exporter qw( import );
use Test::More;

our @EXPORT = qw( shape_ok read_methods );

our %KEYS = (
  'system.info'            => [qw( manufacturer model service_tag serial uuid asset_tag hostname bios_version power_state health cpu_count cpu_model memory_gib )],
  'system.processors'      => [qw( name model cores threads speed_mhz health )],
  'system.memory'          => [qw( name size_mib type speed_mhz manufacturer part_number serial health )],
  'system.nics'            => [qw( name mac speed_mbps link_up health )],
  'power.consumption'      => [qw( watts average_watts min_watts max_watts capacity_watts )],
  'sensors.temperatures'   => [qw( name celsius upper_warning upper_critical lower_warning lower_critical health )],
  'sensors.fans'           => [qw( name reading units health )],
  'sensors.voltages'       => [qw( name volts health )],
  'sensors.power_supplies' => [qw( name model serial firmware capacity_watts input_volts output_watts health )],
  'logs.sel'               => [qw( id created severity message message_id )],
  'logs.lifecycle'         => [qw( id created severity message message_id )],
  'manager.info'           => [qw( model firmware health date_time uuid )],
  'manager.network'        => [qw( hostname fqdn mac ipv4 ipv6 dns )]
);

sub read_methods { sort keys %KEYS }

sub shape_ok {
  my ( $got, $name ) = @_;
  my $want = join ' ', sort @{ $KEYS{$name} or die 'no shape for '.$name };
  my @rows = ref $got eq 'ARRAY' ? @$got : ($got);
  my @bad  = grep { ref $_ ne 'HASH' || join( ' ', sort keys %$_ ) ne $want } @rows;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  return ok( !@bad, $name.': '.( ref $got eq 'ARRAY' ? scalar(@rows).' entries, each' : 'a hash' ).' with exactly the documented keys' )
    || diag( 'documented: '.$want, map { "\ngot: ".( ref $_ eq 'HASH' ? join ' ', sort keys %$_ : $_ // 'undef' ) } @bad );
}

1;
```

`t/15-util.t`:

```perl
#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use JSON::MaybeXS;
use WWW::iDRAC::Util qw( text number health_of state_of list_of );

my @warnings;
local $SIG{__WARN__} = sub { push @warnings, @_ };

subtest 'text' => sub {
  is( text('PowerEdge T330'), 'PowerEdge T330', 'a string' );
  is( text("  PWR SPLY,495W \n"), 'PWR SPLY,495W', 'without padding' );
  is( text(0), '0', 'a zero is a value' );
  is( text($_), undef, 'nothing for '.( defined $_ ? ref $_ ? 'a reference' : "'$_'" : 'undef' ) ) for undef, '', '   ', [], {}, JSON::MaybeXS::true;
};

subtest 'number' => sub {
  is( number(23), 23, 'a number' );
  is( number('4800'), 4800, 'a number in a string' );
  is( number(-7), -7, 'a negative one' );
  is( number(0), 0, 'zero' );
  is( number($_), undef, 'nothing for '.( defined $_ ? ref $_ ? 'a reference' : "'$_'" : 'undef' ) ) for undef, '', 'N/A', [], JSON::MaybeXS::false;
};

subtest 'health_of' => sub {
  is( health_of( { Health => 'OK' } ), 'ok', 'OK' );
  is( health_of( { Health => 'Warning' } ), 'warning', 'Warning' );
  is( health_of( { Health => 'Critical' } ), 'critical', 'Critical' );
  is( health_of($_), undef, 'nothing invented' ) for undef, {}, { Health => undef }, { Health => 'Unknown' }, 'OK', [];
};

subtest 'state_of' => sub {
  is( state_of('On'), 'on', 'On' );
  is( state_of('Off'), 'off', 'Off' );
  is( state_of('PoweringOn'), 'powering_on', 'two words' );
  is( state_of(undef), undef, 'undef' );
};

subtest 'list_of' => sub {
  is_deeply( [ list_of( [ { a => 1 }, undef, 'x', { b => 2 } ] ) ], [ { a => 1 }, { b => 2 } ], 'only the hashes' );
  is_deeply( [ list_of($_) ], [], 'nothing where there is no list' ) for undef, {}, 'x';
};

is_deeply( \@warnings, [], 'no warnings' );

done_testing;
```

`t/40-facade.t`:

```perl
#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';

use FakeiDRAC;
use WWW::iDRAC;

sub error_of (&) { my ( $code ) = @_; eval { $code->(); 1 } ? undef : $@ }

my %login = ( username => 'root', password => 'calvin' );

subtest 'construction' => sub {
  my $idrac = WWW::iDRAC->new( host => 'idrac.example.org', %login );
  is( $idrac->base_url, 'https://idrac.example.org', 'https and the host' );
  is( WWW::iDRAC->new( host => '192.0.2.10:8443', %login )->base_url, 'https://192.0.2.10:8443', 'an address with a port' );
  is( WWW::iDRAC->new( host => '[2001:db8::10]', %login )->base_url, 'https://[2001:db8::10]', 'an IPv6 address' );
  for my $host ( 'https://idrac.example.org', 'idrac.example.org/redfish', 'two words', '' ) {
    isa_ok( error_of { WWW::iDRAC->new( host => $host, %login ) }, 'WWW::iDRAC::Error::Validation', "host '$host'" );
  }
  ok( error_of { WWW::iDRAC->new( host => 'idrac.example.org', username => 'root' ) }, 'the password is required' );
};

subtest 'the user agent' => sub {
  my $default = WWW::iDRAC->new( host => 'idrac.example.org', %login )->ua;
  isa_ok( $default, 'LWP::UserAgent' );
  is( $default->timeout, 60, 'waits 60 seconds' );
  like( $default->agent, qr{\AWWW-iDRAC/}, 'names itself' );
  ok( $default->ssl_opts('verify_hostname'), 'verifies the certificate by default' );
  is( $default->ssl_opts('SSL_verify_mode'), undef, 'and does not touch the verify mode' );

  my $pinned = WWW::iDRAC->new( host => 'idrac.example.org', %login, ssl_fingerprint => 'sha256$ab12', timeout => 10 )->ua;
  is( $pinned->ssl_opts('SSL_fingerprint'), 'sha256$ab12', 'a pinned certificate' );
  ok( $pinned->ssl_opts('verify_hostname'), 'with verification still on' );
  is( $pinned->timeout, 10, 'timeout' );

  is( WWW::iDRAC->new( host => 'idrac.example.org', %login, ssl_ca_file => '/etc/ssl/idrac.pem' )->ua->ssl_opts('SSL_ca_file'), '/etc/ssl/idrac.pem', 'a CA file' );

  my $open = WWW::iDRAC->new( host => 'idrac.example.org', %login, verify_ssl => 0 )->ua;
  ok( !$open->ssl_opts('verify_hostname'), 'verify_ssl => 0 turns the name check off' );
  is( $open->ssl_opts('SSL_verify_mode'), 0, 'and the certificate check' );

  my $own = WWW::iDRAC->new( host => 'idrac.example.org', %login, ssl_opts => { SSL_version => 'TLSv1_2', verify_hostname => 0 } )->ua;
  is( $own->ssl_opts('SSL_version'), 'TLSv1_2', 'ssl_opts are passed on' );
  ok( !$own->ssl_opts('verify_hostname'), 'and win over the defaults' );
};

subtest 'the parts share one transport' => sub {
  my $fake  = FakeiDRAC->new;
  my $idrac = WWW::iDRAC->new( host => $fake->host, %login, ua => $fake );
  isa_ok( $idrac->redfish, 'WWW::iDRAC::Redfish' );
  is( $idrac->redfish->base_url, 'https://idrac.test', 'pointed at the host' );
  is( $idrac->system->redfish, $idrac->redfish, 'system uses the transport of the facade' );
  is( $idrac->system->info->{model}, 'PowerEdge T330', 'and reaches the controller' );
  is( $idrac->logout, 1, 'logout ends the session' );
  is( $fake->sessions, 0, 'on the controller' );

  my $basic = WWW::iDRAC->new( host => $fake->host, %login, ua => $fake, session => 0 );
  $basic->system->info;
  is( $fake->sessions, 0, 'session => 0 reaches the transport' );
};

subtest 'no session is left behind' => sub {
  my $fake = FakeiDRAC->new;
  {
    my $idrac = WWW::iDRAC->new( host => $fake->host, %login, ua => $fake );
    $idrac->system->info;
    is( $fake->sessions, 1, 'open inside the scope' );
  }
  is( $fake->sessions, 0, 'ended when the facade goes away' );

  my $system = WWW::iDRAC->new( host => $fake->host, %login, ua => $fake )->system;
  is( $system->info->{model}, 'PowerEdge T330', 'a part outlives the facade it came from' );
  is( $fake->sessions, 1, 'with its session' );
  undef $system;
  is( $fake->sessions, 0, 'which ends with the part' );
};

done_testing;
```

`t/50-system.t`:

```perl
#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';

use FakeiDRAC;
use iDRACShapes;
use WWW::iDRAC;

my @warnings;
local $SIG{__WARN__} = sub { push @warnings, @_ };

sub error_of (&) { my ( $code ) = @_; eval { $code->(); 1 } ? undef : $@ }

sub idrac { WWW::iDRAC->new( host => $_[0]->host, username => 'root', password => 'calvin', ua => $_[0] ) }

my $path = '/redfish/v1/Systems/System.Embedded.1';

subtest 'info' => sub {
  my $info = idrac( FakeiDRAC->new )->system->info;
  shape_ok( $info, 'system.info' );
  is_deeply( $info, {
    manufacturer => 'Dell Inc.',
    model        => 'PowerEdge T330',
    service_tag  => 'TAG0001',
    serial       => 'SERIAL0001',
    uuid         => '00000000-0000-0000-0000-000000000001',
    asset_tag    => undef,
    hostname     => 'server.example.org',
    bios_version => '2.4.3',
    power_state  => 'on',
    health       => 'ok',
    cpu_count    => 1,
    cpu_model    => 'Intel(R) Xeon(R) CPU E3-1230 v5 @ 3.40GHz',
    memory_gib   => 32
  }, 'translated; an empty asset tag is undef' );
};

subtest 'a system document with nothing in it' => sub {
  my $info = WWW::iDRAC::System->info_from( {} );
  shape_ok( $info, 'system.info' );
  is_deeply( [ grep { defined $info->{$_} } keys %$info ], [], 'every key is there and undef' );
  shape_ok( WWW::iDRAC::System->info_from( { ProcessorSummary => 'n/a', MemorySummary => [], Status => 'OK' } ), 'system.info' );
};

subtest 'processors' => sub {
  my $cpus = idrac( FakeiDRAC->new )->system->processors;
  shape_ok( $cpus, 'system.processors' );
  is_deeply( $cpus, [ { name => 'CPU.Socket.1', model => 'Intel(R) Xeon(R) CPU E3-1230 v5 @ 3.40GHz', cores => 4, threads => 8, speed_mhz => 4000, health => 'ok' } ], 'one processor' );
};

subtest 'nics' => sub {
  my $nics = idrac( FakeiDRAC->new )->system->nics;
  shape_ok( $nics, 'system.nics' );
  is_deeply( $nics, [
    { name => 'NIC.Embedded.1-1-1', mac => '00:00:5E:00:53:01', speed_mbps => 1000, link_up => 1, health => 'ok' },
    { name => 'NIC.Embedded.2-1-1', mac => '00:00:5E:00:53:02', speed_mbps => undef, link_up => 0, health => undef }
  ], 'link state as 1 and 0, the permanent address where there is no other, a missing speed as undef' );
  is( WWW::iDRAC::System->nic_from( {} )->{link_up}, undef, 'an unknown link state is undef, not down' );
};

subtest 'memory' => sub {
  my $fake    = FakeiDRAC->new;
  my $missing = error_of { idrac($fake)->system->memory };
  isa_ok( $missing, 'WWW::iDRAC::Error::Unsupported', 'a controller without a memory collection' );
  is( $missing->capability, 'system.memory', 'names the capability' );
  like( "$missing", qr/\Asystem\.memory is not available on this iDRAC: the controller has no Memory resource\z/, 'and says why' );

  $fake->doc($path)->{Memory} = { '@odata.id' => $path.'/Memory' };
  $fake->{docs}{ $path.'/Memory' } = { Members => [ {
    '@odata.id' => $path.'/Memory/DIMM.Socket.A1', DeviceLocator => 'DIMM A1', CapacityMiB => 16384, MemoryDeviceType => 'DDR4',
    OperatingSpeedMhz => 2133, Manufacturer => 'Micron Technology', PartNumber => '18ASF2G72AZ-2G1A1 ', SerialNumber => 'SERIAL0003', Status => { Health => 'OK' }
  } ] };
  my $memory = idrac($fake)->system->memory;
  shape_ok( $memory, 'system.memory' );
  is_deeply( $memory, [ { name => 'DIMM A1', size_mib => 16384, type => 'DDR4', speed_mhz => 2133, manufacturer => 'Micron Technology', part_number => '18ASF2G72AZ-2G1A1', serial => 'SERIAL0003', health => 'ok' } ], 'one module, the part number without its padding' );

  $fake->doc($path)->{Memory} = { '@odata.id' => $path.'/Gone' };
  isa_ok( error_of { idrac($fake)->system->memory }, 'WWW::iDRAC::Error::Unsupported', 'a link that leads to a 404' );
};

subtest 'supports' => sub {
  my $fake   = FakeiDRAC->new;
  my $system = idrac($fake)->system;
  ok( $system->supports($_), $_ ) for qw( info processors nics );
  ok( !$system->supports('memory'), 'memory is not there' );
  isa_ok( error_of { $system->supports('reboot') }, 'WWW::iDRAC::Error::Validation', 'a name that is no method' );
  isa_ok( error_of { $system->supports(undef) }, 'WWW::iDRAC::Error::Validation', 'no name' );

  my $none = FakeiDRAC->new;
  delete $none->doc('/redfish/v1')->{Systems};
  my $error = error_of { idrac($none)->system->info };
  isa_ok( $error, 'WWW::iDRAC::Error::Unsupported', 'a controller without a system' );
  ok( !idrac($none)->system->supports('info'), 'supports says so' );

  my $down = idrac( FakeiDRAC->new( docs => {} ) )->system;
  isa_ok( error_of { $down->supports('info') }, 'WWW::iDRAC::Error::API', 'an error on the way is not a no' );
};

is_deeply( \@warnings, [], 'no warnings' );

done_testing;
```

- [ ] **Step 2: Laufen lassen und scheitern sehen**

Run: `prove -l t/15-util.t t/40-facade.t t/50-system.t`
Expected: FAIL, `Can't locate WWW/iDRAC/Util.pm in @INC`; `t/40-facade.t` scheitert an `Can't locate object method "new" via package "WWW::iDRAC"`.

- [ ] **Step 3: Util und die Rolle**

`lib/WWW/iDRAC/Util.pm`:

```perl
package WWW::iDRAC::Util;

# ABSTRACT: The small translations every part of WWW::iDRAC needs

use strict;
use warnings;
use Exporter qw( import );
use Scalar::Util qw( looks_like_number );

our $VERSION = '0.001';

our @EXPORT_OK = qw( text number health_of state_of list_of );

=synopsis

    use WWW::iDRAC::Util qw( text number health_of state_of list_of );

=description

Pure functions that turn a value out of a Redfish document into what
WWW::iDRAC returns. None of them does I/O, none of them warns on a value
that is missing.

=cut

sub text {
  my ( $value ) = @_;
  return undef if !defined $value || ref $value;
  ( my $text = $value ) =~ s/\A\s+|\s+\z//g;
  return length $text ? $text : undef;
}

=func text

A string without the padding some firmware adds, or C<undef> for nothing, an
empty string and anything that is not a plain value.

=cut

sub number {
  my ( $value ) = @_;
  return defined $value && !ref $value && looks_like_number($value) ? $value + 0 : undef;
}

=func number

A number, or C<undef> for anything that is none.

=cut

my %HEALTH = ( ok => 'ok', warning => 'warning', critical => 'critical' );

sub health_of {
  my ( $status ) = @_;
  my $health = ref $status eq 'HASH' ? text( $status->{Health} ) : undef;
  return defined $health ? $HEALTH{ lc $health } : undef;
}

=func health_of

    my $health = health_of( $doc->{Status} );

C<ok>, C<warning> or C<critical> out of a Redfish C<Status>, or C<undef> when
the controller does not say.

=cut

sub state_of {
  my ( $value ) = @_;
  my $state = text($value) // return undef;
  $state =~ s/(?<=[a-z])(?=[A-Z])/_/g;
  return lc $state;
}

=func state_of

A Redfish state in lower case with underscores: C<On> becomes C<on>,
C<PoweringOn> becomes C<powering_on>.

=cut

sub list_of {
  my ( $value ) = @_;
  return grep { ref $_ eq 'HASH' } ref $value eq 'ARRAY' ? @$value : ();
}

=func list_of

The hashes of a list, or nothing when there is no list.

=cut

1;
```

`lib/WWW/iDRAC/Role/Capability.pm`:

```perl
package WWW::iDRAC::Role::Capability;

# ABSTRACT: What the capability classes of WWW::iDRAC share

use Scalar::Util qw( blessed );
use WWW::iDRAC::Error::Unsupported;
use WWW::iDRAC::Error::Validation;
use Moo::Role;

our $VERSION = '0.001';

requires 'area';

=description

A capability class answers for one area (C<system>, C<power>, C<sensors>,
C<logs>, C<manager>). It reaches the controller only through L</redfish>,
returns translated data, never raw documents, and turns a resource this
controller does not have into L<WWW::iDRAC::Error::Unsupported>.

Each public method C<x> has a C<probe_x> beside it, which fetches what the
method needs and throws where the method would. L</supports> is built on
those, so its answer comes from what the controller offers.

=cut

has redfish => (
  is       => 'ro',
  required => 1
);

=attr redfish

Required. The L<WWW::iDRAC::Redfish> transport.

=cut

sub unsupported {
  my ( $self, $method, $reason ) = @_;
  my $capability = $self->area.'.'.$method;
  WWW::iDRAC::Error::Unsupported->throw(
    message    => $capability.' is not available on this iDRAC: '.$reason,
    capability => $capability,
    reason     => $reason
  );
}

=method unsupported

    $self->unsupported( cycle => 'reset type PowerCycle is not offered' );

Throws L<WWW::iDRAC::Error::Unsupported> for a method of this area.

=cut

sub _not_found {
  my ( $self, $error ) = @_;
  return blessed $error && $error->isa('WWW::iDRAC::Error::API') && $error->is_not_found;
}

sub fetch {
  my ( $self, $path, $method ) = @_;
  my $doc;
  return $doc if eval { $doc = $self->redfish->get($path); 1 };
  my $error = $@;
  $self->unsupported( $method, $path.' does not exist' ) if $self->_not_found($error);
  die $error;
}

=method fetch

    my $doc = $self->fetch( $path, 'temperatures' );

A document, where a 404 is L<WWW::iDRAC::Error::Unsupported> for the named
method.

=cut

sub fetch_members {
  my ( $self, $path, $method, %arg ) = @_;
  my @docs;
  return @docs if eval { @docs = $self->redfish->members( $path, %arg ); 1 };
  my $error = $@;
  $self->unsupported( $method, $path.' does not exist' ) if $self->_not_found($error);
  die $error;
}

=method fetch_members

    my @docs = $self->fetch_members( $path, 'processors', limit => 10 );

The entries of a collection, with the same treatment of a 404.

=cut

sub resource {
  my ( $self, $kind, $method ) = @_;
  my $path = $self->redfish->locate($kind) // $self->unsupported( $method, 'the controller has no '.$kind.' resource' );
  my $doc  = $self->fetch( $path, $method );
  $self->unsupported( $method, $path.' is empty' ) unless ref $doc eq 'HASH';
  return $doc;
}

=method resource

    my $system = $self->resource( Systems => 'info' );

The current document of the system, the chassis or the manager.

=cut

sub linked_path {
  my ( $self, $doc, $key, $method ) = @_;
  my $link = ref $doc eq 'HASH' ? $doc->{$key} : undef;
  return $link->{'@odata.id'} if ref $link eq 'HASH' && defined $link->{'@odata.id'};
  $self->unsupported( $method, 'the controller has no '.$key.' resource' );
}

=method linked_path

    my $path = $self->linked_path( $chassis, Thermal => 'temperatures' );

The address a document gives for one of its parts.

=cut

sub supports {
  my ( $self, $method ) = @_;
  my $probe = defined $method && $method =~ /\A[a-z_]+\z/ ? $self->can( 'probe_'.$method ) : undef;
  WWW::iDRAC::Error::Validation->throw( message => 'unknown capability '.$self->area.'.'.( $method // '' ) ) unless $probe;
  return 1 if eval { $self->$probe; 1 };
  my $error = $@;
  return 0 if blessed $error && $error->isa('WWW::iDRAC::Error::Unsupported');
  die $error;
}

=method supports

    if ( $idrac->power->supports('cycle') ) { ... }

True when the method of that name can be served by this controller. A name
that is no method of the area is a L<WWW::iDRAC::Error::Validation>; an error
on the way to the answer is thrown as it is.

=cut

1;
```

- [ ] **Step 4: System**

`lib/WWW/iDRAC/System.pm`. Die Service-Tag steht bei Dell im Redfish-Feld `SKU`; ob das auf iDRAC 7/8 so ist, zeigt Aufgabe 12.

```perl
package WWW::iDRAC::System;

# ABSTRACT: Inventory and state of the server behind an iDRAC

use Moo;
use WWW::iDRAC::Util qw( health_of number state_of text );
use namespace::autoclean;

our $VERSION = '0.001';

sub area { 'system' }

with 'WWW::iDRAC::Role::Capability';

=synopsis

    my $info = $idrac->system->info;
    print $info->{model}, ' ', $info->{service_tag}, "\n";

    print $_->{name}, ': ', $_->{size_mib}, "\n" for @{ $idrac->system->memory };

=description

What the server is made of. Every method returns hashes with the keys named
below; a key the controller has nothing for is there and C<undef>.

=cut

sub info {
  my ( $self ) = @_;
  return $self->info_from( $self->resource( Systems => 'info' ) );
}

sub info_from {
  my ( $class, $doc ) = @_;
  my $cpu    = ref $doc->{ProcessorSummary} eq 'HASH' ? $doc->{ProcessorSummary} : {};
  my $memory = ref $doc->{MemorySummary} eq 'HASH'    ? $doc->{MemorySummary}    : {};
  return {
    manufacturer => text( $doc->{Manufacturer} ),
    model        => text( $doc->{Model} ),
    service_tag  => text( $doc->{SKU} ),
    serial       => text( $doc->{SerialNumber} ),
    uuid         => text( $doc->{UUID} ),
    asset_tag    => text( $doc->{AssetTag} ),
    hostname     => text( $doc->{HostName} ),
    bios_version => text( $doc->{BiosVersion} ),
    power_state  => state_of( $doc->{PowerState} ),
    health       => health_of( $doc->{Status} ),
    cpu_count    => number( $cpu->{Count} ),
    cpu_model    => text( $cpu->{Model} ),
    memory_gib   => number( $memory->{TotalSystemMemoryGiB} )
  };
}

=method info

C<manufacturer>, C<model>, C<service_tag>, C<serial>, C<uuid>, C<asset_tag>,
C<hostname>, C<bios_version>, C<power_state>, C<health>, C<cpu_count>,
C<cpu_model>, C<memory_gib>.

=method info_from

    my $info = WWW::iDRAC::System->info_from($system_document);

The translation behind L</info>, without I/O. The same exists for the other
methods as L</processor_from>, L</memory_from> and L</nic_from>.

=cut

sub _parts {
  my ( $self, $key, $method ) = @_;
  my $path = $self->linked_path( $self->resource( Systems => $method ), $key, $method );
  return $self->fetch_members( $path, $method );
}

sub processors {
  my ( $self ) = @_;
  return [ map { $self->processor_from($_) } $self->_parts( Processors => 'processors' ) ];
}

sub processor_from {
  my ( $class, $doc ) = @_;
  return {
    name      => text( $doc->{Socket} ) // text( $doc->{Name} ) // text( $doc->{Id} ),
    model     => text( $doc->{Model} ),
    cores     => number( $doc->{TotalCores} ),
    threads   => number( $doc->{TotalThreads} ),
    speed_mhz => number( $doc->{MaxSpeedMHz} ),
    health    => health_of( $doc->{Status} )
  };
}

=method processors

One hash per processor: C<name>, C<model>, C<cores>, C<threads>,
C<speed_mhz>, C<health>.

=method processor_from

=cut

sub memory {
  my ( $self ) = @_;
  return [ map { $self->memory_from($_) } $self->_parts( Memory => 'memory' ) ];
}

sub memory_from {
  my ( $class, $doc ) = @_;
  return {
    name         => text( $doc->{DeviceLocator} ) // text( $doc->{Name} ) // text( $doc->{Id} ),
    size_mib     => number( $doc->{CapacityMiB} ),
    type         => text( $doc->{MemoryDeviceType} ),
    speed_mhz    => number( $doc->{OperatingSpeedMhz} ),
    manufacturer => text( $doc->{Manufacturer} ),
    part_number  => text( $doc->{PartNumber} ),
    serial       => text( $doc->{SerialNumber} ),
    health       => health_of( $doc->{Status} )
  };
}

=method memory

One hash per memory module: C<name>, C<size_mib>, C<type>, C<speed_mhz>,
C<manufacturer>, C<part_number>, C<serial>, C<health>.

=method memory_from

=cut

sub nics {
  my ( $self ) = @_;
  return [ map { $self->nic_from($_) } $self->_parts( EthernetInterfaces => 'nics' ) ];
}

sub nic_from {
  my ( $class, $doc ) = @_;
  my $link = text( $doc->{LinkStatus} );
  return {
    name       => text( $doc->{Id} ) // text( $doc->{Name} ),
    mac        => text( $doc->{MACAddress} ) // text( $doc->{PermanentMACAddress} ),
    speed_mbps => number( $doc->{SpeedMbps} ),
    link_up    => defined $link ? ( $link eq 'LinkUp' ? 1 : 0 ) : undef,
    health     => health_of( $doc->{Status} )
  };
}

=method nics

One hash per network interface of the server: C<name>, C<mac>,
C<speed_mbps>, C<link_up>, C<health>.

=method nic_from

=cut

sub probe_info       { $_[0]->resource( Systems => 'info' ) }
sub probe_processors { $_[0]->linked_path( $_[0]->resource( Systems => 'processors' ), Processors => 'processors' ) }
sub probe_memory     { $_[0]->linked_path( $_[0]->resource( Systems => 'memory' ), Memory => 'memory' ) }
sub probe_nics       { $_[0]->linked_path( $_[0]->resource( Systems => 'nics' ), EthernetInterfaces => 'nics' ) }

=method probe_info

=method probe_processors

=method probe_memory

=method probe_nics

What L<WWW::iDRAC::Role::Capability/supports> asks.

=cut

1;
```

- [ ] **Step 5: Die Fassade**

`lib/WWW/iDRAC.pm` ersetzt den Stub. Die Synopsis nennt schon die Teile, die die Aufgaben 7 bis 11 nachliefern.

```perl
package WWW::iDRAC;

# ABSTRACT: Perl client for Dell iDRAC - inventory, power, sensors and logs over Redfish

use Moo;
use LWP::UserAgent;
use Types::Standard qw( Bool HashRef InstanceOf Int Str );
use WWW::iDRAC::Error;
use WWW::iDRAC::Error::API;
use WWW::iDRAC::Error::Network;
use WWW::iDRAC::Error::Unsupported;
use WWW::iDRAC::Error::Validation;
use WWW::iDRAC::Redfish;
use WWW::iDRAC::System;
use namespace::autoclean;

our $VERSION = '0.001';

=synopsis

    use WWW::iDRAC;

    my $idrac = WWW::iDRAC->new(
      host            => 'idrac-t330.example.org',
      username        => 'root',
      password        => $ENV{IDRAC_PASSWORD},
      ssl_fingerprint => 'sha256$5f2c...',     # or ssl_ca_file, or verify_ssl => 0
    );

    my $cap = $idrac->capabilities;
    printf "iDRAC %s, firmware %s\n", $cap->generation // '?', $cap->firmware // '?';

    print $idrac->system->info->{service_tag}, "\n";
    print $_->{name}, ': ', $_->{celsius} // '-', "\n" for @{ $idrac->sensors->temperatures };
    print $_->{created}, ' ', $_->{message}, "\n" for @{ $idrac->logs->sel( limit => 10 ) };

    $idrac->power->off;
    $idrac->power->off( force => 1 ) unless $idrac->power->wait_for( 'off', timeout => 300 );

    # what the facade does not cover yet
    my $chassis = $idrac->redfish->get('/redfish/v1/Chassis');

    $idrac->logout;

=description

A client for the management controller of Dell PowerEdge servers. The
methods are cut by what you want to know or do, not by protocol: you ask for
C<< $idrac->system->info >> and do not care how the answer is fetched. In
this version everything is fetched over Redfish.

The methods return plain hashes with fixed keys, not Redfish documents. For
everything they do not cover there is L</redfish>, which hands out the raw
documents.

What a controller can do depends on its generation, its firmware and its
license. A method this controller cannot serve throws
L<WWW::iDRAC::Error::Unsupported> before anything is sent.

=head2 Certificates

An iDRAC ships with a self-signed certificate issued to a name that is not
the address you reach it under. Verification is on anyway. L</ssl_fingerprint>
is the option that fits such a certificate, because a pinned certificate is
accepted whatever name is in it; L</ssl_ca_file> fits a controller that was
given a proper certificate. C<< verify_ssl => 0 >> turns the check off and
is your decision to make, not a default.

WWW::iDRAC does not lower TLS versions or ciphers. A controller that speaks
only what a current OpenSSL refuses needs newer firmware, or your own
settings in L</ssl_opts>.

=cut

has host => (
  is       => 'ro',
  isa      => Str,
  required => 1
);

=attr host

Required. The name or address of the iDRAC, optionally with C<:port>.

=cut

has username => ( is => 'ro', isa => Str, required => 1 );
has password => ( is => 'ro', isa => Str, required => 1 );

=attr username

=attr password

Required.

=cut

has session => (
  is      => 'ro',
  isa     => Bool,
  default => 1
);

=attr session

True by default: one Redfish session for all requests. False sends the
credentials with every request and creates no session.

=cut

has verify_ssl => (
  is      => 'ro',
  isa     => Bool,
  default => 1
);

=attr verify_ssl

True by default. False accepts any certificate.

=cut

has ssl_ca_file     => ( is => 'ro', isa => Str, predicate => 'has_ssl_ca_file' );
has ssl_fingerprint => ( is => 'ro', isa => Str, predicate => 'has_ssl_fingerprint' );

=attr ssl_ca_file

A file with the CA that signed the certificate of the iDRAC.

=attr ssl_fingerprint

The fingerprint of the certificate, as L<IO::Socket::SSL> takes it:
C<sha256$> followed by the hex digits. A certificate with this fingerprint
is accepted without any further check.

=cut

has ssl_opts => (
  is      => 'ro',
  isa     => HashRef,
  default => sub { {} }
);

=attr ssl_opts

Passed on to L<LWP::UserAgent> after the options above, for what they do
not cover.

=cut

has timeout => (
  is      => 'ro',
  isa     => Int,
  default => 60
);

=attr timeout

Seconds to wait for an answer, 60 by default. An iDRAC is slow.

=cut

has ua => (
  is  => 'lazy',
  isa => InstanceOf ['LWP::UserAgent']
);

sub _build_ua {
  my ( $self ) = @_;
  my %ssl = $self->verify_ssl ? ( verify_hostname => 1 ) : ( verify_hostname => 0, SSL_verify_mode => 0 );
  $ssl{SSL_ca_file}     = $self->ssl_ca_file     if $self->has_ssl_ca_file;
  $ssl{SSL_fingerprint} = $self->ssl_fingerprint if $self->has_ssl_fingerprint;
  return LWP::UserAgent->new(
    agent      => 'WWW-iDRAC/'.$VERSION,
    timeout    => $self->timeout,
    keep_alive => 1,
    ssl_opts   => { %ssl, %{ $self->ssl_opts } }
  );
}

=attr ua

The L<LWP::UserAgent>. Give your own and the TLS attributes and L</timeout>
above are not applied.

=cut

sub BUILD {
  my ( $self ) = @_;
  WWW::iDRAC::Error::Validation->throw( message => 'host is a name or an address, optionally with a port, got '.$self->host )
    unless $self->host =~ /\A(?:\[[0-9A-Fa-f:.]+\]|[A-Za-z0-9._-]+)(?::[0-9]+)?\z/;
  return;
}

sub base_url { 'https://'.$_[0]->host }

=method base_url

C<https://> and L</host>.

=cut

has redfish => ( is => 'lazy' );

sub _build_redfish {
  my ( $self ) = @_;
  return WWW::iDRAC::Redfish->new(
    base_url => $self->base_url,
    username => $self->username,
    password => $self->password,
    session  => $self->session,
    ua       => $self->ua
  );
}

=attr redfish

The L<WWW::iDRAC::Redfish> transport. Also the way to everything the facade
does not cover.

=cut

has system => ( is => 'lazy' );

sub _build_system { WWW::iDRAC::System->new( redfish => $_[0]->redfish ) }

=attr system

L<WWW::iDRAC::System>: inventory and state of the server.

=cut

sub logout { $_[0]->redfish->logout }

=method logout

Ends the session. An iDRAC allows only a few at a time, so call this when
you are done. The session is also ended when the last object using it goes
away, but do not rely on that at the very end of a program.

=cut

1;
```

- [ ] **Step 6: `t/00-load.t` ergänzen**

`t/00-load.t`:

```perl
#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

for (qw(
  WWW::iDRAC
  WWW::iDRAC::Error
  WWW::iDRAC::Error::API
  WWW::iDRAC::Error::Network
  WWW::iDRAC::Error::Unsupported
  WWW::iDRAC::Error::Validation
  WWW::iDRAC::Redfish
  WWW::iDRAC::Role::Capability
  WWW::iDRAC::Role::HTTP
  WWW::iDRAC::System
  WWW::iDRAC::Util
)) {
  use_ok($_);
}

done_testing;
```

- [ ] **Step 7: Laufen lassen**

Run: `prove -lr t`
Expected: PASS, 9 Dateien.

- [ ] **Step 8: Übergabe**

Vorschlag: `Add the facade, the capability role and the system inventory`.

---

### Task 7: Power

**Files:**
- Create: `lib/WWW/iDRAC/Power.pm`
- Modify: `lib/WWW/iDRAC.pm`
- Test: `t/51-power.t`
- Modify: `t/00-load.t`

**Interfaces:**
- Consumes: `WWW::iDRAC::Role::Capability` (`resource`, `linked_path`, `fetch`, `unsupported`), `WWW::iDRAC::Util`, `FakeiDRAC` (`delay`), `iDRACShapes`.
- Produces: `WWW::iDRAC::Power` mit `state` → `on`/`off`/Zwischenzustand/`undef`; `on`, `off( force => 1 )`, `restart( force => 1 )`, `cycle` → 1; `wait_for( $state, timeout => 120, interval => 5 )` → 1/0; `consumption` → Hash; `reset_action( $method, $force )` → `( $target, $type )`; `consumption_from($doc)`.
- Produces: `$idrac->power`.

- [ ] **Step 1: Den Test schreiben**

`t/51-power.t`:

```perl
#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';

use FakeiDRAC;
use iDRACShapes;
use WWW::iDRAC;

my @warnings;
local $SIG{__WARN__} = sub { push @warnings, @_ };

sub error_of (&) { my ( $code ) = @_; eval { $code->(); 1 } ? undef : $@ }

sub idrac { WWW::iDRAC->new( host => $_[0]->host, username => 'root', password => 'calvin', ua => $_[0] ) }

my $system = '/redfish/v1/Systems/System.Embedded.1';
my $reset  = $system.'/Actions/ComputerSystem.Reset';

subtest 'state' => sub {
  my $fake  = FakeiDRAC->new;
  my $power = idrac($fake)->power;
  is( $power->state, 'on', 'on' );
  $fake->doc($system)->{PowerState} = 'Off';
  is( $power->state, 'off', 'read anew each time' );
  $fake->doc($system)->{PowerState} = 'PoweringOn';
  is( $power->state, 'powering_on', 'a state in between, in the same form' );
  delete $fake->doc($system)->{PowerState};
  is( $power->state, undef, 'undef when the controller does not say' );
};

subtest 'switching' => sub {
  my $fake  = FakeiDRAC->new;
  my $power = idrac($fake)->power;
  my $sent  = sub { $fake->requests->[-1]->method.' '.$fake->requests->[-1]->uri->path.' '.$fake->requests->[-1]->content };
  is( $power->off, 1, 'off returns true' );
  is( $sent->(), 'POST '.$reset.' {"ResetType":"GracefulShutdown"}', 'and asks for a graceful shutdown at the target the system names' );
  is( $power->state, 'off', 'the server is off' );
  $power->on;
  is( $sent->(), 'POST '.$reset.' {"ResetType":"On"}', 'on' );
  $power->off( force => 1 );
  is( $sent->(), 'POST '.$reset.' {"ResetType":"ForceOff"}', 'off with force' );
  $power->restart;
  is( $sent->(), 'POST '.$reset.' {"ResetType":"GracefulRestart"}', 'restart' );
};

subtest 'an order this controller does not offer' => sub {
  my $fake  = FakeiDRAC->new;
  my $power = idrac($fake)->power;
  $power->state;
  my $posts = $fake->seen(qr/\APOST .*Reset/);
  for my $case ( [ cycle => 'PowerCycle', sub { $power->cycle } ], [ restart => 'ForceRestart', sub { $power->restart( force => 1 ) } ] ) {
    my ( $method, $type, $code ) = @$case;
    my $error = error_of { $code->() };
    isa_ok( $error, 'WWW::iDRAC::Error::Unsupported', $method );
    is( $error->capability, 'power.'.$method, 'names the capability' );
    like( $error->reason, qr/\Areset type $type is not offered, only On, ForceOff, /, 'and what is offered instead' );
  }
  is( scalar $fake->seen(qr/\APOST .*Reset/), $posts, 'nothing was sent' );

  push @{ $fake->doc($system)->{Actions}{'#ComputerSystem.Reset'}{'ResetType@Redfish.AllowableValues'} }, 'PowerCycle';
  is( $power->cycle, 1, 'cycle where it is offered' );
  is( $fake->requests->[-1]->content, '{"ResetType":"PowerCycle"}', 'asks for a power cycle' );

  delete $fake->doc($system)->{Actions}{'#ComputerSystem.Reset'}{'ResetType@Redfish.AllowableValues'};
  is( $power->restart( force => 1 ), 1, 'without a list of allowed values the order is sent' );

  delete $fake->doc($system)->{Actions};
  like( error_of { $power->on }, qr/\Apower\.on is not available on this iDRAC: the system offers no reset action\z/, 'a system without a reset action' );
};

subtest 'wait_for' => sub {
  my $fake  = FakeiDRAC->new( delay => 3 );
  my $power = idrac($fake)->power;
  $power->off;
  is( $power->state, 'on', 'the server takes its time' );
  is( $power->wait_for( 'off', timeout => 30, interval => 0 ), 1, 'true when the state is reached' );
  is( $power->state, 'off', 'which it then is' );
  is( $power->wait_for( 'on', timeout => 0, interval => 0 ), 0, 'false when the time is up' );
  is( $power->wait_for('off'), 1, 'a state already reached returns at once' );
  isa_ok( error_of { $power->wait_for('standby') }, 'WWW::iDRAC::Error::Validation', 'a state that is neither on nor off' );
  isa_ok( error_of { $power->wait_for }, 'WWW::iDRAC::Error::Validation', 'no state' );
};

subtest 'consumption' => sub {
  my $fake = FakeiDRAC->new;
  my $now  = idrac($fake)->power->consumption;
  shape_ok( $now, 'power.consumption' );
  is_deeply( $now, { watts => 87, average_watts => 84, min_watts => 61, max_watts => 143, capacity_watts => 495 }, 'translated' );
  shape_ok( WWW::iDRAC::Power->consumption_from($_), 'power.consumption' ) for {}, { PowerControl => [] }, { PowerControl => [ { PowerMetrics => 'n/a' } ] }, undef;
  delete $fake->doc('/redfish/v1/Chassis/System.Embedded.1')->{Power};
  my $error = error_of { idrac($fake)->power->consumption };
  isa_ok( $error, 'WWW::iDRAC::Error::Unsupported', 'a chassis without a power resource' );
  is( $error->capability, 'power.consumption', 'names the capability' );
};

subtest 'supports' => sub {
  my $power = idrac( FakeiDRAC->new )->power;
  ok( $power->supports($_), $_ ) for qw( state wait_for on off restart consumption );
  ok( !$power->supports('cycle'), 'cycle is not offered' );
  isa_ok( error_of { $power->supports('reset_action') }, 'WWW::iDRAC::Error::Validation', 'a helper is no capability' );
};

is_deeply( \@warnings, [], 'no warnings' );

done_testing;
```

- [ ] **Step 2: Laufen lassen und scheitern sehen**

Run: `prove -l t/51-power.t`
Expected: FAIL, `Can't locate object method "power" via package "WWW::iDRAC"`.

- [ ] **Step 3: Power schreiben**

`lib/WWW/iDRAC/Power.pm`:

```perl
package WWW::iDRAC::Power;

# ABSTRACT: Switching the server behind an iDRAC, and what it draws

use Moo;
use WWW::iDRAC::Error::Validation;
use WWW::iDRAC::Util qw( list_of number state_of );
use namespace::autoclean;

our $VERSION = '0.001';

sub area { 'power' }

with 'WWW::iDRAC::Role::Capability';

=synopsis

    my $power = $idrac->power;

    $power->off;                                    # ask the operating system to shut down
    $power->off( force => 1 ) unless $power->wait_for( 'off', timeout => 300 );
    $power->on;

    print $power->consumption->{watts}, " W\n";

=description

The switching methods return as soon as the controller has accepted the
order; the server takes its time. L</wait_for> waits for the result.

Before an order is sent, the reset type it needs is checked against the ones
the controller offers. A type that is not offered is
L<WWW::iDRAC::Error::Unsupported> and nothing is sent.

=cut

# what each method asks for, gently and with force
my %RESET = (
  on      => [ 'On',               'On' ],
  off     => [ 'GracefulShutdown', 'ForceOff' ],
  restart => [ 'GracefulRestart',  'ForceRestart' ],
  cycle   => [ 'PowerCycle',       'PowerCycle' ]
);

sub state {
  my ( $self ) = @_;
  return state_of( $self->resource( Systems => 'state' )->{PowerState} );
}

=method state

C<on> or C<off>. While the server is on its way the controller may name a
state in between, which is returned in the same form, for example
C<powering_on>.

=cut

sub reset_action {
  my ( $self, $method, $force ) = @_;
  my $type   = $RESET{$method}[ $force ? 1 : 0 ];
  my $doc    = $self->resource( Systems => $method );
  my $action = ref $doc->{Actions} eq 'HASH' ? $doc->{Actions}{'#ComputerSystem.Reset'} : undef;
  $self->unsupported( $method, 'the system offers no reset action' ) unless ref $action eq 'HASH' && defined $action->{target};
  my $allowed = $action->{'ResetType@Redfish.AllowableValues'};
  $self->unsupported( $method, 'reset type '.$type.' is not offered, only '.join( ', ', grep { defined } @$allowed ) )
    if ref $allowed eq 'ARRAY' && !grep { defined && $_ eq $type } @$allowed;
  return ( $action->{target}, $type );
}

=method reset_action

    my ( $target, $type ) = $power->reset_action( off => $force );

Where a switching method sends its order and with which reset type, or
L<WWW::iDRAC::Error::Unsupported>.

=cut

sub _reset {
  my ( $self, $method, %arg ) = @_;
  my ( $target, $type ) = $self->reset_action( $method, $arg{force} );
  $self->redfish->post( $target, { ResetType => $type } );
  return 1;
}

sub on      { $_[0]->_reset('on') }
sub off     { my ( $self, %arg ) = @_; $self->_reset( off => %arg ) }
sub restart { my ( $self, %arg ) = @_; $self->_reset( restart => %arg ) }
sub cycle   { $_[0]->_reset('cycle') }

=method on

Turns the server on.

=method off

    $power->off;
    $power->off( force => 1 );

Asks the operating system to shut down. With C<force> the power is cut.

=method restart

    $power->restart;
    $power->restart( force => 1 );

Asks the operating system to restart. With C<force> the server is reset.

=method cycle

Power off and on again.

=cut

sub wait_for {
  my ( $self, $state, %arg ) = @_;
  WWW::iDRAC::Error::Validation->throw( message => 'wait_for waits for on or off, got '.( $state // 'nothing' ) )
    unless defined $state && ( $state eq 'on' || $state eq 'off' );
  my $interval = $arg{interval} // 5;
  my $deadline = time + ( $arg{timeout} // 120 );
  while (1) {
    return 1 if ( $self->state // '' ) eq $state;
    return 0 if time >= $deadline;
    sleep $interval if $interval;
  }
}

=method wait_for

    my $reached = $power->wait_for( 'off', timeout => 120, interval => 5 );

Asks for L</state> every C<interval> seconds until it is the wanted one.
True when it was reached, false when C<timeout> seconds have passed.

=cut

sub _power_document {
  my ( $self, $method ) = @_;
  return $self->fetch( $self->linked_path( $self->resource( Chassis => $method ), Power => $method ), $method );
}

sub consumption {
  my ( $self ) = @_;
  return $self->consumption_from( $self->_power_document('consumption') );
}

sub consumption_from {
  my ( $class, $doc ) = @_;
  my ( $control ) = list_of( ref $doc eq 'HASH' ? $doc->{PowerControl} : undef );
  my $metrics = $control && ref $control->{PowerMetrics} eq 'HASH' ? $control->{PowerMetrics} : {};
  return {
    watts          => number( $control ? $control->{PowerConsumedWatts} : undef ),
    average_watts  => number( $metrics->{AverageConsumedWatts} ),
    min_watts      => number( $metrics->{MinConsumedWatts} ),
    max_watts      => number( $metrics->{MaxConsumedWatts} ),
    capacity_watts => number( $control ? $control->{PowerCapacityWatts} : undef )
  };
}

=method consumption

C<watts> the server draws now, C<average_watts>, C<min_watts> and
C<max_watts> over the interval the controller measures, and
C<capacity_watts>.

=method consumption_from

    my $consumption = WWW::iDRAC::Power->consumption_from($power_document);

The translation behind L</consumption>, without I/O.

=cut

sub probe_state       { $_[0]->resource( Systems => 'state' ) }
sub probe_wait_for    { $_[0]->resource( Systems => 'wait_for' ) }
sub probe_on          { $_[0]->reset_action('on') }
sub probe_off         { $_[0]->reset_action('off') }
sub probe_restart     { $_[0]->reset_action('restart') }
sub probe_cycle       { $_[0]->reset_action('cycle') }
sub probe_consumption { $_[0]->linked_path( $_[0]->resource( Chassis => 'consumption' ), Power => 'consumption' ) }

=method probe_state

=method probe_wait_for

=method probe_on

=method probe_off

=method probe_restart

=method probe_cycle

=method probe_consumption

What L<WWW::iDRAC::Role::Capability/supports> asks. C<probe_off> and
C<probe_restart> answer for the gentle form.

=cut

1;
```

- [ ] **Step 4: Die Fassade ergänzen**

In `lib/WWW/iDRAC.pm` in den `use`-Block, alphabetisch: `use WWW::iDRAC::Power;`. Und unmittelbar vor `sub logout`:

```perl
has power => ( is => 'lazy' );

sub _build_power { WWW::iDRAC::Power->new( redfish => $_[0]->redfish ) }

=attr power

L<WWW::iDRAC::Power>: switching the server, and what it draws.

=cut
```

- [ ] **Step 5: `t/00-load.t` ergänzen**

In die Liste, alphabetisch: `WWW::iDRAC::Power`.

- [ ] **Step 6: Laufen lassen**

Run: `prove -lr t`
Expected: PASS, 10 Dateien.

- [ ] **Step 7: Übergabe**

Vorschlag: `Add power: state, switching, waiting, consumption`.

---

### Task 8: Sensors

**Files:**
- Create: `lib/WWW/iDRAC/Sensors.pm`
- Modify: `lib/WWW/iDRAC.pm`
- Test: `t/52-sensors.t`
- Modify: `t/00-load.t`

**Interfaces:**
- Consumes: `WWW::iDRAC::Role::Capability`, `WWW::iDRAC::Util`, `FakeiDRAC`, `iDRACShapes`.
- Produces: `WWW::iDRAC::Sensors` mit `temperatures`, `fans`, `voltages`, `power_supplies` → Arrayref von Hashes; `temperature_from`, `fan_from`, `voltage_from`, `power_supply_from`.
- Produces: `$idrac->sensors`.

- [ ] **Step 1: Den Test schreiben**

`t/52-sensors.t`:

```perl
#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';

use FakeiDRAC;
use iDRACShapes;
use WWW::iDRAC;

my @warnings;
local $SIG{__WARN__} = sub { push @warnings, @_ };

sub error_of (&) { my ( $code ) = @_; eval { $code->(); 1 } ? undef : $@ }

sub idrac { WWW::iDRAC->new( host => $_[0]->host, username => 'root', password => 'calvin', ua => $_[0] ) }

my $chassis = '/redfish/v1/Chassis/System.Embedded.1';

subtest 'temperatures' => sub {
  my $t = idrac( FakeiDRAC->new )->sensors->temperatures;
  shape_ok( $t, 'sensors.temperatures' );
  is_deeply( $t, [
    { name => 'System Board Inlet Temp', celsius => 23, upper_warning => 42, upper_critical => 47, lower_warning => 3, lower_critical => -7, health => 'ok' },
    { name => 'CPU2 Temp', celsius => undef, upper_warning => undef, upper_critical => undef, lower_warning => undef, lower_critical => undef, health => undef }
  ], 'a sensor without a reading is listed, with undef' );
};

subtest 'fans' => sub {
  my $fans = idrac( FakeiDRAC->new )->sensors->fans;
  shape_ok( $fans, 'sensors.fans' );
  is_deeply( $fans, [
    { name => 'System Board Fan1', reading => 4800, units => 'RPM', health => 'ok' },
    { name => 'System Board Fan2', reading => 0, units => 'RPM', health => 'critical' }
  ], 'the name from either field, a reading of zero kept' );
};

subtest 'voltages' => sub {
  my $v = idrac( FakeiDRAC->new )->sensors->voltages;
  shape_ok( $v, 'sensors.voltages' );
  is_deeply( $v, [ { name => 'PS1 Voltage 1', volts => 230, health => 'ok' }, { name => 'System Board 3.3V PG', volts => undef, health => 'ok' } ], 'translated' );
};

subtest 'power supplies' => sub {
  my $fake = FakeiDRAC->new;
  my $ps   = idrac($fake)->sensors->power_supplies;
  shape_ok( $ps, 'sensors.power_supplies' );
  is_deeply( $ps, [ { name => 'PS1 Status', model => 'PWR SPLY,495W,RDNT,DELTA', serial => 'SERIAL0002', firmware => '00.1D.7D', capacity_watts => 495, input_volts => 230, output_watts => 87, health => 'warning' } ], 'translated, the model without its padding' );
  is( WWW::iDRAC::Sensors->power_supply_from( { PowerOutputWatts => 90 } )->{output_watts}, 90, 'the output under its newer name' );
};

subtest 'documents that are not what they should be' => sub {
  my $fake = FakeiDRAC->new;
  %{ $fake->doc( $chassis.'/Thermal' ) } = ( Temperatures => 'none', Fans => undef );
  is_deeply( idrac($fake)->sensors->temperatures, [], 'no list of temperatures is an empty list' );
  is_deeply( idrac($fake)->sensors->fans, [], 'no list of fans' );
  shape_ok( WWW::iDRAC::Sensors->temperature_from( { ReadingCelsius => 'N/A', Status => 'OK' } ), 'sensors.temperatures' );
};

subtest 'a chassis without sensors' => sub {
  my $fake = FakeiDRAC->new;
  delete $fake->doc($chassis)->{Thermal};
  $fake->remove( $chassis.'/Power' );
  my $sensors = idrac($fake)->sensors;
  for my $method (qw( temperatures fans voltages power_supplies )) {
    my $error = error_of { $sensors->$method };
    isa_ok( $error, 'WWW::iDRAC::Error::Unsupported', $method );
    is( $error->capability, 'sensors.'.$method, 'names the capability' );
  }
  ok( !$sensors->supports('temperatures'), 'supports: no thermal resource' );
  ok( $sensors->supports('voltages'), 'supports follows the link, not the document behind it' );
  ok( idrac( FakeiDRAC->new )->sensors->supports($_), $_ ) for qw( temperatures fans voltages power_supplies );
};

is_deeply( \@warnings, [], 'no warnings' );

done_testing;
```

- [ ] **Step 2: Laufen lassen und scheitern sehen**

Run: `prove -l t/52-sensors.t`
Expected: FAIL, `Can't locate object method "sensors" via package "WWW::iDRAC"`.

- [ ] **Step 3: Sensors schreiben**

`lib/WWW/iDRAC/Sensors.pm`:

```perl
package WWW::iDRAC::Sensors;

# ABSTRACT: Temperatures, fans, voltages and power supplies of a server

use Moo;
use WWW::iDRAC::Util qw( health_of list_of number text );
use namespace::autoclean;

our $VERSION = '0.001';

sub area { 'sensors' }

with 'WWW::iDRAC::Role::Capability';

=synopsis

    for my $t ( @{ $idrac->sensors->temperatures } ) {
      next unless defined $t->{celsius};
      print $t->{name}, ': ', $t->{celsius}, "\n";
    }

=description

What the chassis measures. A sensor the controller lists without a reading,
an empty socket for example, is listed here too, with the reading C<undef>.

=cut

sub _document {
  my ( $self, $key, $method ) = @_;
  return $self->fetch( $self->linked_path( $self->resource( Chassis => $method ), $key, $method ), $method );
}

sub temperatures {
  my ( $self ) = @_;
  return [ map { $self->temperature_from($_) } list_of( $self->_document( Thermal => 'temperatures' )->{Temperatures} ) ];
}

sub temperature_from {
  my ( $class, $doc ) = @_;
  return {
    name           => text( $doc->{Name} ),
    celsius        => number( $doc->{ReadingCelsius} ),
    upper_warning  => number( $doc->{UpperThresholdNonCritical} ),
    upper_critical => number( $doc->{UpperThresholdCritical} ),
    lower_warning  => number( $doc->{LowerThresholdNonCritical} ),
    lower_critical => number( $doc->{LowerThresholdCritical} ),
    health         => health_of( $doc->{Status} )
  };
}

=method temperatures

One hash per sensor: C<name>, C<celsius>, C<upper_warning>,
C<upper_critical>, C<lower_warning>, C<lower_critical>, C<health>.

=method temperature_from

    my $t = WWW::iDRAC::Sensors->temperature_from($entry);

The translation of one entry, without I/O. The same exists as L</fan_from>,
L</voltage_from> and L</power_supply_from>.

=cut

sub fans {
  my ( $self ) = @_;
  return [ map { $self->fan_from($_) } list_of( $self->_document( Thermal => 'fans' )->{Fans} ) ];
}

sub fan_from {
  my ( $class, $doc ) = @_;
  return {
    name    => text( $doc->{FanName} ) // text( $doc->{Name} ),
    reading => number( $doc->{Reading} ),
    units   => text( $doc->{ReadingUnits} ),
    health  => health_of( $doc->{Status} )
  };
}

=method fans

One hash per fan: C<name>, C<reading>, C<units> (C<RPM> or C<Percent>),
C<health>.

=method fan_from

=cut

sub voltages {
  my ( $self ) = @_;
  return [ map { $self->voltage_from($_) } list_of( $self->_document( Power => 'voltages' )->{Voltages} ) ];
}

sub voltage_from {
  my ( $class, $doc ) = @_;
  return {
    name   => text( $doc->{Name} ),
    volts  => number( $doc->{ReadingVolts} ),
    health => health_of( $doc->{Status} )
  };
}

=method voltages

One hash per voltage sensor: C<name>, C<volts>, C<health>.

=method voltage_from

=cut

sub power_supplies {
  my ( $self ) = @_;
  return [ map { $self->power_supply_from($_) } list_of( $self->_document( Power => 'power_supplies' )->{PowerSupplies} ) ];
}

sub power_supply_from {
  my ( $class, $doc ) = @_;
  return {
    name           => text( $doc->{Name} ),
    model          => text( $doc->{Model} ),
    serial         => text( $doc->{SerialNumber} ),
    firmware       => text( $doc->{FirmwareVersion} ),
    capacity_watts => number( $doc->{PowerCapacityWatts} ),
    input_volts    => number( $doc->{LineInputVoltage} ),
    output_watts   => number( $doc->{LastPowerOutputWatts} ) // number( $doc->{PowerOutputWatts} ),
    health         => health_of( $doc->{Status} )
  };
}

=method power_supplies

One hash per power supply: C<name>, C<model>, C<serial>, C<firmware>,
C<capacity_watts>, C<input_volts>, C<output_watts>, C<health>.

=method power_supply_from

=cut

sub probe_temperatures   { $_[0]->linked_path( $_[0]->resource( Chassis => 'temperatures' ),   Thermal => 'temperatures' ) }
sub probe_fans           { $_[0]->linked_path( $_[0]->resource( Chassis => 'fans' ),           Thermal => 'fans' ) }
sub probe_voltages       { $_[0]->linked_path( $_[0]->resource( Chassis => 'voltages' ),       Power   => 'voltages' ) }
sub probe_power_supplies { $_[0]->linked_path( $_[0]->resource( Chassis => 'power_supplies' ), Power   => 'power_supplies' ) }

=method probe_temperatures

=method probe_fans

=method probe_voltages

=method probe_power_supplies

What L<WWW::iDRAC::Role::Capability/supports> asks.

=cut

1;
```

- [ ] **Step 4: Die Fassade ergänzen**

In den `use`-Block: `use WWW::iDRAC::Sensors;`. Vor `sub logout`:

```perl
has sensors => ( is => 'lazy' );

sub _build_sensors { WWW::iDRAC::Sensors->new( redfish => $_[0]->redfish ) }

=attr sensors

L<WWW::iDRAC::Sensors>: temperatures, fans, voltages, power supplies.

=cut
```

- [ ] **Step 5: `t/00-load.t` ergänzen**

In die Liste: `WWW::iDRAC::Sensors`.

- [ ] **Step 6: Laufen lassen**

Run: `prove -lr t`
Expected: PASS, 11 Dateien.

- [ ] **Step 7: Übergabe**

Vorschlag: `Add sensors: temperatures, fans, voltages, power supplies`.

---

### Task 9: Logs

**Files:**
- Create: `lib/WWW/iDRAC/Logs.pm`
- Modify: `lib/WWW/iDRAC.pm`
- Test: `t/53-logs.t`
- Modify: `t/00-load.t`

**Interfaces:**
- Consumes: `WWW::iDRAC::Role::Capability` (`fetch_members` mit `limit`), `WWW::iDRAC::Util`, `FakeiDRAC`, `iDRACShapes`.
- Produces: `WWW::iDRAC::Logs` mit `sel( limit => 50 )`, `lifecycle( limit => 50 )` → Arrayref von Hashes, neueste zuerst; `clear_sel` → 1; `service( $id, $method )`, `entries( $id, $method, limit => $n )`, `clear_action`, `entry_from($doc)`.
- Produces: `$idrac->logs`.

- [ ] **Step 1: Den Test schreiben**

`t/53-logs.t`:

```perl
#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';

use FakeiDRAC;
use iDRACShapes;
use WWW::iDRAC;

my @warnings;
local $SIG{__WARN__} = sub { push @warnings, @_ };

sub error_of (&) { my ( $code ) = @_; eval { $code->(); 1 } ? undef : $@ }

sub idrac { WWW::iDRAC->new( host => $_[0]->host, username => 'root', password => 'calvin', ua => $_[0] ) }

my $manager = '/redfish/v1/Managers/iDRAC.Embedded.1';

subtest 'sel' => sub {
  my $sel = idrac( FakeiDRAC->new )->logs->sel;
  shape_ok( $sel, 'logs.sel' );
  is_deeply( [ map { $_->{id} } @$sel ], [ 3, 2, 1 ], 'newest first' );
  is_deeply( $sel->[1], { id => '2', created => '2026-10-02T08:00:00+02:00', severity => 'critical', message => 'Fan 2 failed.', message_id => 'FAN0001' }, 'translated, the severity in lower case' );
};

subtest 'lifecycle' => sub {
  my $fake = FakeiDRAC->new;
  my $log  = idrac($fake)->logs->lifecycle;
  shape_ok( $log, 'logs.lifecycle' );
  is_deeply( [ map { $_->{id} } @$log ], [ 3, 2, 1 ], 'all pages' );
  is( $log->[2]{severity}, 'informational', 'a severity that is no health level is kept' );
  my $two = idrac($fake)->logs->lifecycle( limit => 2 );
  is_deeply( [ map { $_->{id} } @$two ], [ 3, 2 ], 'limit takes the front of the list' );
  isa_ok( error_of { idrac($fake)->logs->lifecycle( limit => 'all' ) }, 'WWW::iDRAC::Error::Validation', 'a limit that is no number' );
};

subtest 'the default limit' => sub {
  my $fake = FakeiDRAC->new;
  $fake->doc( $manager.'/Logs/Sel' )->{Members} = [ map { { '@odata.id' => $manager.'/Logs/Sel/'.$_, Id => "$_", Created => sprintf( '2026-09-%02dT00:00:%02d+02:00', 1 + int( $_ / 60 ), $_ % 60 ) } } 1 .. 120 ];
  is( scalar @{ idrac($fake)->logs->sel }, 50, '50 entries unless told otherwise' );
  is( scalar @{ idrac($fake)->logs->sel( limit => 120 ) }, 120, 'more on request' );
};

subtest 'entries without a date' => sub {
  my $entry = WWW::iDRAC::Logs->entry_from( {} );
  shape_ok( $entry, 'logs.sel' );
  is_deeply( [ grep { defined $entry->{$_} } keys %$entry ], [], 'every key is there and undef' );
  my $fake = FakeiDRAC->new;
  delete $fake->doc( $manager.'/Logs/Sel' )->{Members}[0]{Created};
  is_deeply( [ map { $_->{id} } @{ idrac($fake)->logs->sel } ], [ 3, 1, 2 ], 'sort last' );
};

subtest 'clear_sel' => sub {
  my $fake = FakeiDRAC->new;
  my $logs = idrac($fake)->logs;
  is( $logs->clear_sel, 1, 'returns true' );
  is( $fake->requests->[-1]->method.' '.$fake->requests->[-1]->uri->path, 'POST '.$manager.'/LogServices/Sel/Actions/LogService.ClearLog', 'at the target the log service names' );
  is_deeply( $logs->sel, [], 'the log is empty' );
};

subtest 'a controller without these logs' => sub {
  my $fake = FakeiDRAC->new;
  my $logs = idrac($fake)->logs;
  ok( $logs->supports($_), $_ ) for qw( sel lifecycle clear_sel );
  ok( !eval { $logs->supports('clear_lifecycle'); 1 }, 'there is no clear_lifecycle' );

  delete $fake->doc( $manager.'/LogServices/Sel' )->{Actions};
  my $posts = $fake->seen(qr/\APOST .*ClearLog/);
  my $error = error_of { $logs->clear_sel };
  isa_ok( $error, 'WWW::iDRAC::Error::Unsupported', 'a log service without a clear action' );
  is( $error->capability, 'logs.clear_sel', 'names the capability' );
  is( scalar $fake->seen(qr/\APOST .*ClearLog/), $posts, 'nothing was sent' );

  $fake->doc( $manager.'/LogServices' )->{Members} = [ { '@odata.id' => $manager.'/LogServices/Sel' } ];
  like( error_of { $logs->lifecycle }, qr/\Alogs\.lifecycle is not available on this iDRAC: the controller has no log service lclog\z/, 'no lifecycle log' );
  ok( !$logs->supports('lifecycle'), 'supports says so' );

  delete $fake->doc( $manager.'/LogServices/Sel' )->{Id};
  is( scalar @{ $logs->sel }, 3, 'a service without an Id is found by its address' );

  delete $fake->doc($manager)->{LogServices};
  isa_ok( error_of { $logs->sel }, 'WWW::iDRAC::Error::Unsupported', 'a manager without log services' );
};

is_deeply( \@warnings, [], 'no warnings' );

done_testing;
```

- [ ] **Step 2: Laufen lassen und scheitern sehen**

Run: `prove -l t/53-logs.t`
Expected: FAIL, `Can't locate object method "logs" via package "WWW::iDRAC"`.

- [ ] **Step 3: Logs schreiben**

`lib/WWW/iDRAC/Logs.pm`. `limit` nimmt die ersten Einträge, wie der Controller sie liefert; dass das die neuesten sind, ist eine Annahme, die die Live-Suite in Aufgabe 13 prüft.

```perl
package WWW::iDRAC::Logs;

# ABSTRACT: The system event log and the lifecycle log of an iDRAC

use Moo;
use WWW::iDRAC::Util qw( text );
use namespace::autoclean;

our $VERSION = '0.001';

sub area { 'logs' }

with 'WWW::iDRAC::Role::Capability';

=synopsis

    print $_->{created}, ' ', $_->{severity}, ' ', $_->{message}, "\n" for @{ $idrac->logs->sel( limit => 20 ) };

    $idrac->logs->clear_sel;

=description

The two logs an iDRAC keeps: the system event log of the hardware and the
lifecycle log of the controller. Both are found through the log services the
manager lists, by their names C<Sel> and C<Lclog>.

C<limit> is the number of entries fetched, 50 unless given, taken from the
front of the list as the controller serves it, which is newest first on an
iDRAC. The entries fetched are returned newest first.

=cut

sub service {
  my ( $self, $id, $method ) = @_;
  my $path = $self->linked_path( $self->resource( Managers => $method ), LogServices => $method );
  for my $service ( $self->fetch_members( $path, $method ) ) {
    my $name = text( $service->{Id} ) // ( ( $service->{'@odata.id'} // '' ) =~ m{([^/]+)/?\z} )[0] // '';
    return $service if lc $name eq $id;
  }
  $self->unsupported( $method, 'the controller has no log service '.$id );
}

=method service

    my $doc = $logs->service( sel => 'clear_sel' );

The document of the log service C<sel> or C<lclog>.

=cut

sub entries {
  my ( $self, $id, $method, %arg ) = @_;
  my $path    = $self->linked_path( $self->service( $id, $method ), Entries => $method );
  my @entries = map { $self->entry_from($_) } $self->fetch_members( $path, $method, limit => $arg{limit} // 50 );
  return [ sort { ( $b->{created} // '' ) cmp ( $a->{created} // '' ) } @entries ];
}

sub entry_from {
  my ( $class, $doc ) = @_;
  my $severity = text( $doc->{Severity} );
  return {
    id         => text( $doc->{Id} ),
    created    => text( $doc->{Created} ),
    severity   => defined $severity ? lc $severity : undef,
    message    => text( $doc->{Message} ),
    message_id => text( $doc->{MessageId} )
  };
}

=method entries

    my $entries = $logs->entries( sel => 'sel', limit => 50 );

What L</sel> and L</lifecycle> are made of.

=method entry_from

    my $entry = WWW::iDRAC::Logs->entry_from($entry_document);

The translation of one entry, without I/O.

=cut

sub sel       { my ( $self, %arg ) = @_; $self->entries( sel   => 'sel',       %arg ) }
sub lifecycle { my ( $self, %arg ) = @_; $self->entries( lclog => 'lifecycle', %arg ) }

=method sel

    my $entries = $logs->sel( limit => 50 );

The system event log. One hash per entry: C<id>, C<created>, C<severity> in
lower case, C<message>, C<message_id>.

=method lifecycle

    my $entries = $logs->lifecycle( limit => 50 );

The lifecycle log, in the same form.

=cut

sub clear_action {
  my ( $self ) = @_;
  my $service = $self->service( sel => 'clear_sel' );
  my $action  = ref $service->{Actions} eq 'HASH' ? $service->{Actions}{'#LogService.ClearLog'} : undef;
  $self->unsupported( clear_sel => 'the log service offers no clear action' ) unless ref $action eq 'HASH' && defined $action->{target};
  return $action->{target};
}

sub clear_sel {
  my ( $self ) = @_;
  $self->redfish->post( $self->clear_action, {} );
  return 1;
}

=method clear_sel

Empties the system event log.

=method clear_action

Where L</clear_sel> sends its order, or L<WWW::iDRAC::Error::Unsupported>.

=cut

sub probe_sel       { $_[0]->linked_path( $_[0]->service( sel   => 'sel' ),       Entries => 'sel' ) }
sub probe_lifecycle { $_[0]->linked_path( $_[0]->service( lclog => 'lifecycle' ), Entries => 'lifecycle' ) }
sub probe_clear_sel { $_[0]->clear_action }

=method probe_sel

=method probe_lifecycle

=method probe_clear_sel

What L<WWW::iDRAC::Role::Capability/supports> asks.

=cut

1;
```

- [ ] **Step 4: Die Fassade ergänzen**

In den `use`-Block: `use WWW::iDRAC::Logs;`. Vor `sub logout`:

```perl
has logs => ( is => 'lazy' );

sub _build_logs { WWW::iDRAC::Logs->new( redfish => $_[0]->redfish ) }

=attr logs

L<WWW::iDRAC::Logs>: the system event log and the lifecycle log.

=cut
```

- [ ] **Step 5: `t/00-load.t` ergänzen**

In die Liste: `WWW::iDRAC::Logs`.

- [ ] **Step 6: Laufen lassen**

Run: `prove -lr t`
Expected: PASS, 12 Dateien.

- [ ] **Step 7: Übergabe**

Vorschlag: `Add logs: the system event log and the lifecycle log`.

---

### Task 10: Manager

**Files:**
- Create: `lib/WWW/iDRAC/Manager.pm`
- Modify: `lib/WWW/iDRAC.pm`
- Test: `t/54-manager.t`
- Modify: `t/00-load.t`

**Interfaces:**
- Consumes: `WWW::iDRAC::Role::Capability`, `WWW::iDRAC::Util`, `WWW::iDRAC::Redfish::forget_session`, `FakeiDRAC`, `iDRACShapes`.
- Produces: `WWW::iDRAC::Manager` mit `info`, `network` → Hash; `restart` → 1; `reset_action` → Ziel; `info_from($doc)`, `network_from($doc)`.
- Produces: `$idrac->manager`.

- [ ] **Step 1: Den Test schreiben**

`t/54-manager.t`:

```perl
#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';

use FakeiDRAC;
use iDRACShapes;
use WWW::iDRAC;

my @warnings;
local $SIG{__WARN__} = sub { push @warnings, @_ };

sub error_of (&) { my ( $code ) = @_; eval { $code->(); 1 } ? undef : $@ }

sub idrac { WWW::iDRAC->new( host => $_[0]->host, username => 'root', password => 'calvin', ua => $_[0] ) }

my $manager = '/redfish/v1/Managers/iDRAC.Embedded.1';
my $system  = '/redfish/v1/Systems/System.Embedded.1';

subtest 'info' => sub {
  my $info = idrac( FakeiDRAC->new )->manager->info;
  shape_ok( $info, 'manager.info' );
  is_deeply( $info, { model => '13G Monolithic', firmware => '2.83.83.83', health => 'ok', date_time => '2026-10-04T12:00:00+02:00', uuid => '00000000-0000-0000-0000-000000000002' }, 'translated' );
  shape_ok( WWW::iDRAC::Manager->info_from( {} ), 'manager.info' );
};

subtest 'network' => sub {
  my $network = idrac( FakeiDRAC->new )->manager->network;
  shape_ok( $network, 'manager.network' );
  is_deeply( $network, {
    hostname => 'idrac-TAG0001',
    fqdn     => 'idrac-TAG0001.example.org',
    mac      => '00:00:5E:00:53:10',
    ipv4     => ['192.0.2.10'],
    ipv6     => ['2001:db8::10'],
    dns      => ['192.0.2.53']
  }, 'addresses as lists, the ones that are not set left out' );
  my $empty = WWW::iDRAC::Manager->network_from( { IPv4Addresses => 'none', NameServers => { a => 1 } } );
  shape_ok( $empty, 'manager.network' );
  is_deeply( [ @$empty{qw( ipv4 ipv6 dns )} ], [ [], [], [] ], 'the lists are lists even when the controller sends none' );
};

subtest 'restart' => sub {
  my $fake  = FakeiDRAC->new;
  my $idrac = idrac($fake);
  $idrac->manager->info;
  is( $idrac->manager->restart, 1, 'returns true' );
  is( $fake->requests->[-1]->method.' '.$fake->requests->[-1]->uri->path.' '.$fake->requests->[-1]->content, 'POST '.$manager.'/Actions/Manager.Reset {"ResetType":"GracefulRestart"}', 'a graceful restart at the target the manager names' );
  is( $fake->doc($system)->{PowerState}, 'On', 'the server keeps running' );
  my $before = @{ $fake->requests };
  $idrac->manager->info;
  is_deeply( [ map { $_->method } @{ $fake->requests }[ $before .. $#{ $fake->requests } ] ], [ 'POST', 'GET' ], 'the next request logs in first, instead of sending the token the restart made void' );
  is( scalar $fake->seen(qr/\ADELETE/), 0, 'and nothing tries to end the session the restart ended' );
};

subtest 'a controller that offers less' => sub {
  my $fake    = FakeiDRAC->new;
  my $manager_part = idrac($fake)->manager;
  ok( $manager_part->supports($_), $_ ) for qw( info network restart );

  $fake->doc($manager)->{Actions}{'#Manager.Reset'}{'ResetType@Redfish.AllowableValues'} = ['ForceRestart'];
  my $posts = $fake->seen(qr/\APOST .*Manager\.Reset/);
  my $error = error_of { $manager_part->restart };
  isa_ok( $error, 'WWW::iDRAC::Error::Unsupported', 'a reset type that is not offered' );
  is( $error->capability, 'manager.restart', 'names the capability' );
  is( scalar $fake->seen(qr/\APOST .*Manager\.Reset/), $posts, 'nothing was sent' );

  $fake->doc( $manager.'/EthernetInterfaces' )->{Members} = [];
  like( error_of { $manager_part->network }, qr/\Amanager\.network is not available on this iDRAC: the controller lists no network interface\z/, 'no network interface' );
  delete $fake->doc($manager)->{EthernetInterfaces};
  ok( !$manager_part->supports('network'), 'supports: no interfaces at all' );
};

is_deeply( \@warnings, [], 'no warnings' );

done_testing;
```

- [ ] **Step 2: Laufen lassen und scheitern sehen**

Run: `prove -l t/54-manager.t`
Expected: FAIL, `Can't locate object method "manager" via package "WWW::iDRAC"`.

- [ ] **Step 3: Manager schreiben**

`lib/WWW/iDRAC/Manager.pm`:

```perl
package WWW::iDRAC::Manager;

# ABSTRACT: The iDRAC itself - what it is, how it is reached, restarting it

use Moo;
use WWW::iDRAC::Util qw( health_of list_of text );
use namespace::autoclean;

our $VERSION = '0.001';

sub area { 'manager' }

with 'WWW::iDRAC::Role::Capability';

=synopsis

    print $idrac->manager->info->{firmware}, "\n";
    print join( ', ', @{ $idrac->manager->network->{ipv4} } ), "\n";

    $idrac->manager->restart;      # the controller, not the server

=cut

sub info {
  my ( $self ) = @_;
  return $self->info_from( $self->resource( Managers => 'info' ) );
}

sub info_from {
  my ( $class, $doc ) = @_;
  return {
    model     => text( $doc->{Model} ),
    firmware  => text( $doc->{FirmwareVersion} ),
    health    => health_of( $doc->{Status} ),
    date_time => text( $doc->{DateTime} ),
    uuid      => text( $doc->{UUID} )
  };
}

=method info

C<model>, C<firmware>, C<health>, C<date_time> as the controller's own clock
reads, C<uuid>.

=method info_from

    my $info = WWW::iDRAC::Manager->info_from($manager_document);

The translation behind L</info>, without I/O.

=cut

sub network {
  my ( $self ) = @_;
  my $path = $self->linked_path( $self->resource( Managers => 'network' ), EthernetInterfaces => 'network' );
  my ( $interface ) = $self->fetch_members( $path, 'network', limit => 1 );
  $self->unsupported( network => 'the controller lists no network interface' ) unless ref $interface eq 'HASH';
  return $self->network_from($interface);
}

sub network_from {
  my ( $class, $doc ) = @_;
  my $addresses = sub { [ grep { defined } map { text( $_->{Address} ) } list_of( $_[0] ) ] };
  # an unset address comes as all zeroes; leave those out
  my $set = sub { [ grep { $_ ne '0.0.0.0' && $_ ne '::' } @{ $_[0] } ] };
  return {
    hostname => text( $doc->{HostName} ),
    fqdn     => text( $doc->{FQDN} ),
    mac      => text( $doc->{MACAddress} ) // text( $doc->{PermanentMACAddress} ),
    ipv4     => $set->( $addresses->( $doc->{IPv4Addresses} ) ),
    ipv6     => $set->( $addresses->( $doc->{IPv6Addresses} ) ),
    dns      => $set->( [ grep { defined } map { text($_) } ref $doc->{NameServers} eq 'ARRAY' ? @{ $doc->{NameServers} } : () ] )
  };
}

=method network

How the controller is reached: C<hostname>, C<fqdn>, C<mac>, and the lists
C<ipv4>, C<ipv6> and C<dns> of addresses. Addresses that are not set are
left out.

=method network_from

    my $network = WWW::iDRAC::Manager->network_from($interface_document);

The translation behind L</network>, without I/O.

=cut

sub reset_action {
  my ( $self ) = @_;
  my $doc    = $self->resource( Managers => 'restart' );
  my $action = ref $doc->{Actions} eq 'HASH' ? $doc->{Actions}{'#Manager.Reset'} : undef;
  $self->unsupported( restart => 'the manager offers no reset action' ) unless ref $action eq 'HASH' && defined $action->{target};
  my $allowed = $action->{'ResetType@Redfish.AllowableValues'};
  $self->unsupported( restart => 'reset type GracefulRestart is not offered, only '.join( ', ', grep { defined } @$allowed ) )
    if ref $allowed eq 'ARRAY' && !grep { defined && $_ eq 'GracefulRestart' } @$allowed;
  return $action->{target};
}

sub restart {
  my ( $self ) = @_;
  $self->redfish->post( $self->reset_action, { ResetType => 'GracefulRestart' } );
  # the controller forgets its sessions when it restarts
  $self->redfish->forget_session;
  return 1;
}

=method restart

Restarts the iDRAC. The server keeps running. The controller is away for a
few minutes afterwards, and requests in that time end in
L<WWW::iDRAC::Error::Network>.

=method reset_action

Where L</restart> sends its order, or L<WWW::iDRAC::Error::Unsupported>.

=cut

sub probe_info    { $_[0]->resource( Managers => 'info' ) }
sub probe_network { $_[0]->linked_path( $_[0]->resource( Managers => 'network' ), EthernetInterfaces => 'network' ) }
sub probe_restart { $_[0]->reset_action }

=method probe_info

=method probe_network

=method probe_restart

What L<WWW::iDRAC::Role::Capability/supports> asks.

=cut

1;
```

- [ ] **Step 4: Die Fassade ergänzen**

In den `use`-Block: `use WWW::iDRAC::Manager;`. Vor `sub logout`:

```perl
has manager => ( is => 'lazy' );

sub _build_manager { WWW::iDRAC::Manager->new( redfish => $_[0]->redfish ) }

=attr manager

L<WWW::iDRAC::Manager>: the iDRAC itself.

=cut
```

- [ ] **Step 5: `t/00-load.t` ergänzen**

In die Liste: `WWW::iDRAC::Manager`.

- [ ] **Step 6: Laufen lassen**

Run: `prove -lr t`
Expected: PASS, 13 Dateien.

- [ ] **Step 7: Übergabe**

Vorschlag: `Add manager: the controller itself, its network, restarting it`.

---

### Task 11: Capabilities

**Files:**
- Create: `lib/WWW/iDRAC/Capabilities.pm`
- Modify: `lib/WWW/iDRAC.pm`
- Test: `t/60-capabilities.t`
- Modify: `t/00-load.t`

**Interfaces:**
- Consumes: `WWW::iDRAC::Redfish` (`root`, `locate`, `get`), `supports` der fünf Fähigkeits-Klassen, `WWW::iDRAC::Util`.
- Produces: `WWW::iDRAC::Capabilities->new( redfish =>, areas => { system =>, power =>, sensors =>, logs =>, manager => } )` mit `facts` → `{ generation, model, firmware, redfish_version, license }`, den gleichnamigen Methoden, `supports('area.method')` → 1/0, `facts_from( root =>, system =>, manager => )`, `generation_from($model)`.
- Produces: `$idrac->capabilities`.

- [ ] **Step 1: Den Test schreiben**

`t/60-capabilities.t`:

```perl
#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';

use FakeiDRAC;
use iDRACShapes;
use WWW::iDRAC;

my @warnings;
local $SIG{__WARN__} = sub { push @warnings, @_ };

sub error_of (&) { my ( $code ) = @_; eval { $code->(); 1 } ? undef : $@ }

sub idrac { WWW::iDRAC->new( host => $_[0]->host, username => 'root', password => 'calvin', ua => $_[0] ) }

my $manager = '/redfish/v1/Managers/iDRAC.Embedded.1';

subtest 'facts' => sub {
  my $fake = FakeiDRAC->new;
  my $cap  = idrac($fake)->capabilities;
  is_deeply( $cap->facts, { generation => 8, model => 'PowerEdge T330', firmware => '2.83.83.83', redfish_version => '1.0.2', license => undef }, 'the five facts' );
  is( $cap->generation, 8, 'generation' );
  is( $cap->model, 'PowerEdge T330', 'model of the server' );
  is( $cap->firmware, '2.83.83.83', 'firmware of the controller' );
  is( $cap->redfish_version, '1.0.2', 'Redfish version' );
  is( $cap->license, undef, 'the license is not read in this version' );
  my $before = @{ $fake->requests };
  $cap->generation for 1 .. 3;
  is( scalar @{ $fake->requests }, $before, 'read once' );
};

subtest 'generation' => sub {
  my %want = ( '12G Monolithic' => 7, '12G Modular' => 7, '13G Monolithic' => 8, '14G Monolithic' => 9, '15G Monolithic' => 9, '16G Monolithic' => 9, '17G Monolithic' => 10 );
  is( WWW::iDRAC::Capabilities->generation_from($_), $want{$_}, $_ ) for sort keys %want;
  is( WWW::iDRAC::Capabilities->generation_from($_), undef, 'undef for '.( $_ // 'undef' ) ) for undef, '', 'iDRAC', '11G Monolithic', 'G13', [];
};

subtest 'a controller that says little' => sub {
  my $fake = FakeiDRAC->new;
  delete $fake->doc('/redfish/v1')->{Managers};
  delete $fake->doc('/redfish/v1/Systems/System.Embedded.1')->{Links};
  delete $fake->doc('/redfish/v1/Systems/System.Embedded.1')->{Model};
  is_deeply( idrac($fake)->capabilities->facts, { generation => undef, model => undef, firmware => undef, redfish_version => '1.0.2', license => undef }, 'undef for what it does not say' );
};

subtest 'supports' => sub {
  my $fake = FakeiDRAC->new;
  my $cap  = idrac($fake)->capabilities;
  ok( $cap->supports($_), $_ ) for qw( system.info system.nics power.on power.off power.consumption sensors.temperatures logs.sel logs.clear_sel manager.info manager.restart );
  ok( !$cap->supports($_), 'not '.$_ ) for qw( power.cycle system.memory );
  push @{ $fake->doc('/redfish/v1/Systems/System.Embedded.1')->{Actions}{'#ComputerSystem.Reset'}{'ResetType@Redfish.AllowableValues'} }, 'PowerCycle';
  ok( $cap->supports('power.cycle'), 'asked anew each time' );
  for my $name ( 'power', 'power.', 'storage.volumes', 'power.explode', 'Power.on', '', undef, [] ) {
    isa_ok( error_of { $cap->supports($name) }, 'WWW::iDRAC::Error::Validation', 'unknown: '.( defined $name ? ref $name ? 'a reference' : "'$name'" : 'undef' ) );
  }
};

subtest 'the capabilities outlive the facade' => sub {
  my $fake = FakeiDRAC->new;
  my $cap  = idrac($fake)->capabilities;
  is( $cap->generation, 8, 'facts' );
  ok( $cap->supports('power.on'), 'supports' );
  undef $cap;
  is( $fake->sessions, 0, 'and the session ends with them' );
};

is_deeply( \@warnings, [], 'no warnings' );

done_testing;
```

- [ ] **Step 2: Laufen lassen und scheitern sehen**

Run: `prove -l t/60-capabilities.t`
Expected: FAIL, `Can't locate object method "capabilities" via package "WWW::iDRAC"`.

- [ ] **Step 3: Capabilities schreiben**

`lib/WWW/iDRAC/Capabilities.pm`. Die Generation kommt aus dem Modell, das der Manager meldet und das die Server-Generation nennt (12G ist iDRAC 7, 13G iDRAC 8, 14G bis 16G iDRAC 9, 17G iDRAC 10). Hat Aufgabe 5 gezeigt, dass ein Controller sein Modell anders meldet, wird `generation_from` hier um diese Form erweitert, mit dem gemessenen Wert als Testfall in `t/60-capabilities.t`.

```perl
package WWW::iDRAC::Capabilities;

# ABSTRACT: What this iDRAC is and what it can do

use Moo;
use Types::Standard qw( HashRef );
use WWW::iDRAC::Error::Validation;
use WWW::iDRAC::Util qw( text );
use namespace::autoclean;

our $VERSION = '0.001';

=synopsis

    my $cap = $idrac->capabilities;

    printf "iDRAC %s, firmware %s, on a %s\n", $cap->generation // '?', $cap->firmware // '?', $cap->model // '?';

    $idrac->power->cycle if $cap->supports('power.cycle');

=description

The facts are read once, on first use. L</supports> asks the controller
each time, because what it offers can change with the state of the server.

=cut

has redfish => (
  is       => 'ro',
  required => 1
);

=attr redfish

Required. The L<WWW::iDRAC::Redfish> transport.

=cut

has areas => (
  is       => 'ro',
  isa      => HashRef,
  required => 1
);

=attr areas

Required. The capability objects by the name of their area.

=cut

has facts => ( is => 'lazy' );

sub _build_facts {
  my ( $self ) = @_;
  my %doc = ( root => $self->redfish->root );
  for my $part ( [ system => 'Systems' ], [ manager => 'Managers' ] ) {
    my $path = $self->redfish->locate( $part->[1] );
    my $doc  = defined $path ? $self->redfish->get($path) : undef;
    $doc{ $part->[0] } = ref $doc eq 'HASH' ? $doc : {};
  }
  return $self->facts_from(%doc);
}

sub facts_from {
  my ( $class, %doc ) = @_;
  return {
    generation      => $class->generation_from( $doc{manager}{Model} ),
    model           => text( $doc{system}{Model} ),
    firmware        => text( $doc{manager}{FirmwareVersion} ),
    redfish_version => text( $doc{root}{RedfishVersion} ),
    license         => undef
  };
}

=attr facts

The five facts below as one hash.

=method facts_from

    my $facts = WWW::iDRAC::Capabilities->facts_from( root => $root, system => $system, manager => $manager );

The translation behind L</facts>, without I/O.

=cut

sub generation_from {
  my ( $class, $model ) = @_;
  my ( $server ) = ( text($model) // '' ) =~ /\b([0-9]{2})G\b/ or return undef;
  return $server == 12 ? 7 : $server == 13 ? 8 : $server >= 14 && $server <= 16 ? 9 : $server >= 17 ? 10 : undef;
}

=method generation_from

    my $generation = WWW::iDRAC::Capabilities->generation_from('13G Monolithic');    # 8

The generation of the iDRAC out of the model the manager reports, which
names the generation of the server: 12G is iDRAC 7, 13G is iDRAC 8, 14G to
16G are iDRAC 9, 17G is iDRAC 10.

=cut

sub generation      { $_[0]->facts->{generation} }
sub model           { $_[0]->facts->{model} }
sub firmware        { $_[0]->facts->{firmware} }
sub redfish_version { $_[0]->facts->{redfish_version} }
sub license         { $_[0]->facts->{license} }

=method generation

7, 8, 9 or 10, or C<undef> when the controller does not say.

=method model

The model of the server, for example C<PowerEdge T330>.

=method firmware

The firmware version of the iDRAC.

=method redfish_version

The version of Redfish the controller speaks.

=method license

C<undef> in this version: the license is not read yet.

=cut

sub supports {
  my ( $self, $name ) = @_;
  my ( $area, $method ) = defined $name && !ref $name ? $name =~ /\A([a-z]+)\.([a-z_]+)\z/ : ();
  WWW::iDRAC::Error::Validation->throw( message => 'unknown capability '.( $name // '' ) )
    unless defined $area && $self->areas->{$area};
  return $self->areas->{$area}->supports($method);
}

=method supports

    if ( $cap->supports('power.cycle') ) { ... }

True when this controller can serve the method of that name, given as
C<area.method>. The answer comes from what the controller offers, the
resources it has and the values its actions allow, not from a table of
versions. A name that is no method is a L<WWW::iDRAC::Error::Validation>.

=cut

1;
```

- [ ] **Step 4: Die Fassade ergänzen**

In den `use`-Block: `use WWW::iDRAC::Capabilities;`. Vor `sub logout`:

```perl
has capabilities => ( is => 'lazy' );

sub _build_capabilities {
  my ( $self ) = @_;
  return WWW::iDRAC::Capabilities->new(
    redfish => $self->redfish,
    areas   => { map { $_ => $self->$_ } qw( system power sensors logs manager ) }
  );
}

=attr capabilities

L<WWW::iDRAC::Capabilities>: what this controller is and what it can do.

=cut
```

- [ ] **Step 5: `t/00-load.t` ersetzen**

`t/00-load.t`:

```perl
#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

for (qw(
  WWW::iDRAC
  WWW::iDRAC::Capabilities
  WWW::iDRAC::Error
  WWW::iDRAC::Error::API
  WWW::iDRAC::Error::Network
  WWW::iDRAC::Error::Unsupported
  WWW::iDRAC::Error::Validation
  WWW::iDRAC::Logs
  WWW::iDRAC::Manager
  WWW::iDRAC::Power
  WWW::iDRAC::Redfish
  WWW::iDRAC::Role::Capability
  WWW::iDRAC::Role::HTTP
  WWW::iDRAC::Sensors
  WWW::iDRAC::System
  WWW::iDRAC::Util
)) {
  use_ok($_);
}

done_testing;
```

- [ ] **Step 6: Laufen lassen**

Run: `prove -lr t`
Expected: PASS, 14 Dateien.

- [ ] **Step 7: Übergabe**

Vorschlag: `Add capabilities: what this controller is, and supports`.

---

### Task 12: Jede lesende Methode gegen jede Aufnahme

Hier trifft der Code zum ersten Mal auf das, was echte Controller antworten. Der Test ist kurz; die Arbeit dieser Aufgabe ist, was er findet.

**Files:**
- Test: `t/85-fixtures.t`
- Modify: je nach Befund die Fähigkeits-Klasse und ihr Test

**Interfaces:**
- Consumes: `FakeiDRAC->from_file`, `iDRACShapes` (`read_methods`, `shape_ok`), `t/fixtures/*/redfish.json` (Aufgabe 5), alle Fähigkeits-Klassen.

- [ ] **Step 1: Den Test schreiben**

`t/85-fixtures.t`:

```perl
#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';

# Every reading method against every controller there is a recording of in
# t/fixtures/, and against the invented one. A method either returns exactly
# the documented keys or says that this controller does not have it. Anything
# else, another error or a warning, is a defect.

use Scalar::Util qw( blessed );
use FakeiDRAC;
use iDRACShapes;
use WWW::iDRAC;

my %controller = ( 'the invented controller' => sub { FakeiDRAC->new } );
for my $file ( sort glob 't/fixtures/*/redfish.json' ) {
  my ( $name ) = $file =~ m{t/fixtures/([^/]+)/};
  $controller{$name} = sub { FakeiDRAC->from_file($file) };
}

for my $name ( sort keys %controller ) {
  subtest $name => sub {
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    my $fake  = $controller{$name}->();
    my $idrac = WWW::iDRAC->new( host => $fake->host, username => 'root', password => 'calvin', ua => $fake );

    my $facts = eval { $idrac->capabilities->facts };
    is( ref $facts, 'HASH', 'the facts are readable' ) or diag $@;
    note sprintf 'iDRAC %s, firmware %s, %s, Redfish %s', map { $_ // '?' } @{ $facts || {} }{qw( generation firmware model redfish_version )};

    for my $method ( read_methods() ) {
      my ( $area, $call ) = split /\./, $method;
      my $got;
      if ( eval { $got = $idrac->$area->$call; 1 } ) {
        shape_ok( $got, $method );
        ok( $idrac->capabilities->supports($method), $method.': supports agrees' );
      }
      else {
        my $error = $@;
        ok( blessed $error && $error->isa('WWW::iDRAC::Error::Unsupported'), $method.': not on this controller' ) or diag $error;
        note $error;
        ok( !$idrac->capabilities->supports($method), $method.': supports agrees' );
      }
    }

    like( $idrac->power->state // 'undef', qr/\A[a-z_]+\z/, 'power.state' );
    ok( defined eval { $idrac->capabilities->supports($_) }, $_.': supports answers' ) or diag $@
      for qw( power.on power.off power.restart power.cycle logs.clear_sel manager.restart );
    is( scalar $fake->seen(qr/\A(?:POST(?! \S*Sessions\z)|PATCH|PUT)/), 0, 'reading changes nothing on the controller' );
    is_deeply( \@warnings, [], 'no warnings' );
  };
}

done_testing;
```

- [ ] **Step 2: Laufen lassen**

Run: `prove -lv t/85-fixtures.t`
Expected: je ein Subtest für `idrac7`, `idrac8` und `the invented controller`. Fehlen die Aufnahmen noch, läuft nur der dritte; dann bleibt diese Aufgabe offen, bis Aufgabe 5 erledigt ist.

Beim ersten Lauf mit einer neuen Aufnahme scheitert ihr Subtest an `there is no t/fixtures/<name>/expect.json` und druckt, was die Aufnahme zeigt: welche Methoden `Unsupported` sind, welche eine leere Liste liefern und welche Schlüssel in jeder Zeile `undef` sind. Diese Liste ist der Befund dieser Aufgabe. Jeder Schlüssel unter `undef` ist entweder ein Feld, das dieser Controller nicht liefert (bleibt stehen), oder eines, das der Code unter falschem Namen sucht (Fehler, Vorgehen wie in Step 3). Erst wenn sie stimmt, wird sie als `expect.json` gespeichert.

- [ ] **Step 3: Befunde abarbeiten**

Für jede Zeile, die nicht `ok` ist, gilt dasselbe Vorgehen:

1. Das Dokument aus der Aufnahme heraussuchen, an dem die Methode scheitert (`perl -MJSON::PP -e 'my ( $file, $path ) = @ARGV; open my $fh, "<", $file or die $!; local $/; print JSON::PP->new->pretty->canonical->encode( JSON::PP->new->decode(<$fh>)->{$path} )' t/fixtures/idrac7/redfish.json '<Pfad>'`).
2. In der Test-Datei der Klasse (`t/50-system.t` bis `t/54-manager.t`) einen Subtest schreiben, der die `*_from`-Funktion mit genau diesem Ausschnitt aufruft und das richtige Ergebnis verlangt. Laufen lassen, scheitern sehen.
3. Die Klasse ändern. Die Schlüssel in `t/lib/iDRACShapes.pm` bleiben, wie sie sind; es ändert sich nur, woher ein Wert kommt.
4. `prove -lr t`.

Was ein Befund ist und was nicht:

| Zeile im Test | Bedeutung | Handlung |
|---|---|---|
| `<method>: not on this controller`, als `ok` | Der Controller hat die Ressource nicht. Richtig so. | In Spec-Abschnitt 9 eintragen, welche Methoden auf welchem Gerät `Unsupported` sind. |
| `shape_ok` scheitert | Die Übersetzung liefert andere Schlüssel. | Fehler in der Klasse; wie oben. |
| ein anderer Fehler als `Unsupported` | Der Code kommt mit einem Dokument nicht zurecht. | Fehler in der Klasse; wie oben. |
| `no warnings` scheitert | Ein Wert hat eine Form, mit der `Util` nicht rechnet. | Testfall in `t/15-util.t`, dann `Util` ändern. |
| alle Schlüssel einer Methode sind `undef` | Der Controller nennt die Felder anders. | Kein Testfehler, aber ein Befund: mit `prove -lv` und einem `diag explain` nachsehen, Feldnamen aus der Aufnahme ergänzen, mit Testfall. |

Für den letzten Fall, einmal über beide Aufnahmen:

```bash
for n in idrac7 idrac8; do perl -Ilib -It/lib -MFakeiDRAC -MWWW::iDRAC -MiDRACShapes -e '
  my $fake  = FakeiDRAC->from_file("t/fixtures/$ARGV[0]/redfish.json");
  my $idrac = WWW::iDRAC->new( host => $fake->host, username => "root", password => "calvin", ua => $fake );
  for my $m ( read_methods() ) {
    my ( $area, $call ) = split /\./, $m;
    my $got = eval { $idrac->$area->$call } or next;
    my ( $row ) = ref $got eq "ARRAY" ? @$got : $got or next;
    my @undef = grep { !defined $row->{$_} } sort keys %$row;
    printf "%s %-24s undef: %s\n", $ARGV[0], $m, join " ", @undef if @undef;
  }' $n; done
```

Jeder Schlüssel in dieser Liste wird entweder aus der Aufnahme gefüllt oder in Spec-Abschnitt 9 als „liefert dieser Controller nicht“ vermerkt.

- [ ] **Step 4: Übergabe**

Vorschlag: `Run every reading method against the recorded controllers`, mit den Korrekturen aus Step 3 im selben Commit oder je Befund einem eigenen.

---

### Task 13: Live-Suite, README, CLAUDE.md, Changes

**Files:**
- Test: `t/90-live-idrac.t`
- Modify: `README.md`, `CLAUDE.md`, `Changes` (jeweils ganz ersetzen)

**Interfaces:**
- Consumes: alles aus den Aufgaben 2 bis 12.

- [ ] **Step 1: Die Live-Suite schreiben**

`t/90-live-idrac.t`:

```perl
#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib 't/lib';

# Live test against a real iDRAC. Off unless IDRAC_HOST, IDRAC_USERNAME and
# IDRAC_PASSWORD are set. IDRAC_SSL_FINGERPRINT pins the certificate,
# IDRAC_VERIFY_SSL=0 accepts any.
#
# As it is, the test only reads. With IDRAC_LIVE_DESTRUCTIVE=1 it also empties
# the system event log, switches the server off and on again and restarts the
# controller. That hits a real machine: do not set it for one that is in use.

BEGIN {
  plan skip_all => 'set IDRAC_HOST, IDRAC_USERNAME and IDRAC_PASSWORD to run the iDRAC live test'
    unless 3 == grep { defined $ENV{$_} && length $ENV{$_} } qw( IDRAC_HOST IDRAC_USERNAME IDRAC_PASSWORD );
}

use Scalar::Util qw( blessed );
use iDRACShapes;
use WWW::iDRAC;

my $idrac = WWW::iDRAC->new(
  host     => $ENV{IDRAC_HOST},
  username => $ENV{IDRAC_USERNAME},
  password => $ENV{IDRAC_PASSWORD},
  ( $ENV{IDRAC_SSL_FINGERPRINT} ? ( ssl_fingerprint => $ENV{IDRAC_SSL_FINGERPRINT} ) : () ),
  verify_ssl => $ENV{IDRAC_VERIFY_SSL} // 1
);
my $cap = $idrac->capabilities;

END { eval { $idrac->logout } if $idrac }

sub unsupported { blessed $_[0] && $_[0]->isa('WWW::iDRAC::Error::Unsupported') }

subtest 'the controller' => sub {
  my $facts = $cap->facts;
  diag sprintf 'iDRAC %s, firmware %s, %s, Redfish %s', map { $_ // '?' } @$facts{qw( generation firmware model redfish_version )};
  ok( defined $facts->{redfish_version}, 'speaks Redfish' );
  ok( defined $facts->{firmware}, 'names its firmware' );
  like( $facts->{generation} // '', qr/\A(?:7|8|9|10)\z/, 'and its generation is recognised' );
};

subtest 'reading' => sub {
  for my $method ( read_methods() ) {
    my ( $area, $call ) = split /\./, $method;
    my $got;
    if ( eval { $got = $idrac->$area->$call; 1 } ) {
      shape_ok( $got, $method );
      ok( $cap->supports($method), $method.': supports agrees' );
    }
    else {
      my $error = $@;
      ok( unsupported($error), $method.': not on this controller' ) or diag $error;
      diag $error;
      ok( !$cap->supports($method), $method.': supports agrees' );
    }
  }
  like( $idrac->power->state // 'undef', qr/\A[a-z_]+\z/, 'power.state' );
  diag sprintf '%-18s %s', $_.':', $cap->supports($_) ? 'yes' : 'no' for qw( power.on power.off power.restart power.cycle logs.clear_sel manager.restart );
};

subtest 'what the design assumes' => sub {
  my $info = $idrac->system->info;
  ok( defined $info->{service_tag}, 'the service tag is where it is looked for' );
  ok( defined $info->{model}, 'the model' );
  for my $log (qw( sel lifecycle )) {
    my $entries = eval { $idrac->logs->$log( limit => 10 ) } or next;
    my @created = grep { defined } map { $_->{created} } @$entries;
    next unless @created > 1;
    my $all  = eval { $idrac->logs->$log( limit => 200 ) } || [];
    my @full = grep { defined } map { $_->{created} } @$all;
    is( $created[0], $full[0], $log.': the first entries the controller serves are the newest' );
  }
};

subtest 'sessions' => sub {
  is( $idrac->logout, 1, 'logout ends the session' );
  ok( defined $idrac->power->state, 'and the next request opens a new one' );
};

subtest 'changing things' => sub {
  plan skip_all => 'set IDRAC_LIVE_DESTRUCTIVE=1 to empty the event log, switch the server and restart the controller' unless $ENV{IDRAC_LIVE_DESTRUCTIVE};

  SKIP: {
    skip 'logs.clear_sel is not on this controller', 2 unless $cap->supports('logs.clear_sel');
    is( $idrac->logs->clear_sel, 1, 'clear_sel' );
    cmp_ok( scalar @{ $idrac->logs->sel }, '<=', 2, 'the event log is empty, but for what the clearing itself logs' );
  }

  SKIP: {
    my $power = $idrac->power;
    my $start = $power->state // '';
    skip 'the server is neither on nor off but '.$start, 4 unless $start eq 'on' || $start eq 'off';
    skip 'power.on is not on this controller', 4 unless $cap->supports('power.on');
    my $gentle = $cap->supports('power.off');
    diag 'power.off is not on this controller, the power is cut instead' unless $gentle;
    my %step = (
      off => sub { $gentle ? $power->off : $power->off( force => 1 ) },
      on  => sub { $power->on }
    );
    for my $want ( $start eq 'on' ? qw( off on ) : qw( on off ) ) {
      is( $step{$want}->(), 1, 'power '.$want );
      ok( $power->wait_for( $want, timeout => 600, interval => 10 ), 'the server is '.$want );
    }
  }

  SKIP: {
    skip 'manager.restart is not on this controller', 2 unless $cap->supports('manager.restart');
    is( $idrac->manager->restart, 1, 'manager restart' );
    my $back;
    for ( 1 .. 60 ) {
      sleep( $ENV{IDRAC_LIVE_PAUSE} // 10 );
      last if $back = eval { $idrac->manager->info };
    }
    ok( $back, 'the controller is back' );
  }
};

done_testing;
```

- [ ] **Step 2: Ohne Gerät laufen lassen**

Run: `prove -lr t`
Expected: PASS, 16 Dateien; `t/90-live-idrac.t` ist `skipped: set IDRAC_HOST, IDRAC_USERNAME and IDRAC_PASSWORD to run the iDRAC live test`.

- [ ] **Step 3: Lesend gegen beide Geräte**

Braucht die Dateien aus Aufgabe 5. `IDRAC_LIVE_DESTRUCTIVE` bleibt ungesetzt.

```bash
cd ~/dev/p5-www-idrac
( set -a; . ~/.config/idrac/t330.env;   set +a; prove -lv t/90-live-idrac.t ) 2>&1 | tee /tmp/idrac8-live.txt
( set -a; . ~/.config/idrac/r720xd.env; set +a; prove -lv t/90-live-idrac.t ) 2>&1 | tee /tmp/idrac7-live.txt
```

Expected: `Result: PASS` für beide; der Subtest `changing things` ist übersprungen. Die `diag`-Zeilen nennen Generation, Firmware und was `supports` für die schaltenden Methoden antwortet.

Scheitert `the first entries the controller serves are the newest`, liefert dieser Controller seine Logs älteste zuerst. Dann stimmt die Annahme hinter `limit` nicht: Notiz auf die Karte, Getty entscheidet, ob `logs` in dem Fall alle Einträge holt.

Scheitert etwas anderes, ist das ein Unterschied zwischen Aufnahme und Gerät; Vorgehen wie in Aufgabe 12, Step 3.

- [ ] **Step 4: Der schaltende Teil — nur Getty**

Diesen Schritt führt kein Agent aus. Er leert das Event-Log, schaltet den Server aus und wieder ein und startet den iDRAC neu. Getty entscheidet, ob und an welchem Gerät:

```bash
( set -a; . ~/.config/idrac/t330.env; set +a; IDRAC_LIVE_DESTRUCTIVE=1 prove -lv t/90-live-idrac.t )
```

Bietet der Controller kein sanftes Herunterfahren an, wird das Schalten übersprungen. Den Strom hart abzuschalten erlaubt erst ein zweiter Schalter:

```bash
( set -a; . ~/.config/idrac/t330.env; set +a; IDRAC_LIVE_DESTRUCTIVE=1 IDRAC_LIVE_FORCE_OFF=1 prove -lv t/90-live-idrac.t )
```

Das Ergebnis, oder dass der Lauf nicht stattgefunden hat, steht in der Übergabe.

- [ ] **Step 5: README**

`README.md`:

````markdown
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
`WWW::iDRAC::Error::Unsupported` before anything is sent. Developed against iDRAC 7
(PowerEdge R720xd) and iDRAC 8 (PowerEdge T330).

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
````

- [ ] **Step 6: CLAUDE.md**

`CLAUDE.md`:

````markdown
# CLAUDE.md

WWW::iDRAC — synchronous Perl client for Dell iDRAC: inventory, power, sensors, logs and
the controller itself, behind a facade cut by capability, not by protocol. Phase 1 fetches
everything over Redfish. Moo-based; released to CPAN via Dist::Zilla `[@Author::GETTY]`.

**Phase 1 is built** against iDRAC 7 (PowerEdge R720xd) and iDRAC 8 (PowerEdge T330). The
design is `docs/superpowers/specs/2026-10-04-www-idrac-design.md`, the plan
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
off and on and restart the controller. Never set it yourself; it hits a real machine.

`LICENSE` is committed, not generated at build time; re-run `dzil genlicense` and
`git add LICENSE` after changing license, holder or year in `dist.ini`.
````

- [ ] **Step 7: Changes**

`Changes`:

```
Revision history for WWW-iDRAC

{{$NEXT}}
    - Facade WWW::iDRAC for one controller: host, credentials, TLS options
    - WWW::iDRAC::Redfish: the transport and the way to everything the facade
      does not cover; session login, one new login when the token is refused,
      collections with and without embedded entries, the session ended when
      the object goes away
    - WWW::iDRAC::System: info, processors, memory, nics
    - WWW::iDRAC::Power: state, on, off, restart, cycle, wait_for, consumption
    - WWW::iDRAC::Sensors: temperatures, fans, voltages, power supplies
    - WWW::iDRAC::Logs: the system event log and the lifecycle log, clear_sel
    - WWW::iDRAC::Manager: info, network, restart
    - WWW::iDRAC::Capabilities: generation, model, firmware, Redfish version,
      and supports('area.method'), answered from what the controller offers
    - All methods return hashes with fixed keys, never Redfish documents; a
      key the controller has nothing for is there and undef
    - WWW::iDRAC::Error with ::Validation, ::Network, ::API and ::Unsupported;
      what a controller does not have is Unsupported before anything is sent
    - Certificates are verified by default; ssl_fingerprint pins the
      self-signed certificate an iDRAC ships with
    - Recorded answers of an iDRAC 7 (PowerEdge R720xd) and an iDRAC 8
      (PowerEdge T330) as fixtures, and a recorder that cleans them
    - Live tests against a real iDRAC behind IDRAC_HOST, read-only unless
      IDRAC_LIVE_DESTRUCTIVE is set
```

- [ ] **Step 8: Alles zusammen**

```bash
cd ~/dev/p5-www-idrac && git add -A && prove -lr t && dzil test --all
grep -rn 'Embedded\.1' lib/ | grep -v '^\S*:[0-9]*:    '
```

Expected: `prove` PASS mit 16 Dateien, `dzil test --all` endet mit `all's well`. Das `grep` findet nichts: Feste Ressourcennamen stehen unter `lib/` nur in eingerückten POD-Beispielen.

Meldet `dzil test` POD-Fehler, gehen sie an `www-idrac-doc-writer`; die Listings dieses Plans sind nicht durch `dzil` gelaufen.

- [ ] **Step 9: Übergabe**

Vorschlag: `Add the live suite and the documentation of phase 1`. Der Release-Manager setzt danach Karte 2 auf `done`. Ein Release und ein GitHub-Repo sind nicht Teil dieses Plans.
