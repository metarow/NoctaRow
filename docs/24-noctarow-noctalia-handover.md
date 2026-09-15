---
titel: Noctalia startet nicht — Diagnose, Fix, Rollout-Falle
teil_von: "[[README]]"
tags: [noctarow, noctalia, quickshell, diagnose, bootc, handover]
erstellt: 2026-08-25
status: abgeschlossen
---

# 24 — Noctalia startet nicht: Diagnose, Fix, Rollout-Falle

**Projekt:** Noctarow (bootc-Image, Fedora Sway Atomic 44 + Noctalia + Homebrew-Toolchain)
**Repo-Artefakte:** `Containerfile`, `terra.repo`, `overlay/`, `scripts/noctarow.nu`
**Stand:** 2026-08-25 — Fix im Image (4.1, 4.2), Abhängigkeiten geprüft (4.3),
Rollout-Check ergänzt (4.4), QML-Baum nach `/usr` gespiegelt (5),
Upstream-Stand v4→v5 geprüft und Paket-Rename auf `noctalia-legacy`
nachvollzogen (6). Alle Abschnitte abgearbeitet. **Live auf dem ASUS
X515JA verifiziert** ([[hosts/asus-x515ja/README|Host-Override]]) —
mit einem Nachtrag zur Ursachendiagnose, siehe Warnkasten in Abschnitt 3.

---

## 1. Ausgangssymptom

Nach dem Boot des Images war die Noctalia-Shell nicht sichtbar: keine Bar, keine Panels.
Der Verdacht lag zunächst auf einem fehlgeschlagenen Paket-Install.

## 2. Diagnoseverlauf

Ergebnisse der Prüfung im Container (`podman run --rm localhost/noctarow:44 …`):

| Prüfung | Ergebnis | Schlussfolgerung |
|---|---|---|
| `rpm -V noctalia-shell` | keine Ausgabe | Payload vollständig und unverändert |
| `rpm -ql \| grep -E "^/(opt\|var\|usr/local)/"` | keine Treffer | kein ostree-Pfadproblem |
| `rpm -qa \| grep -iE "noctalia\|quickshell"` | `noctalia-qs-0.0.12-5.fc44`, `noctalia-shell-4.7.7-1.fc44` | beide Pakete da |
| `ls /usr/bin \| grep -iE "noct\|^qs$"` | nur `qs` | **kein Binary `noctalia-shell`** |
| `rpm -ql noctalia-shell` | alles unter `/etc/xdg/quickshell/noctalia-shell/` | reine Quickshell-Config, kein Programm |

Auf dem gebooteten System:

```
$ pgrep -a qs
1398 qs -p /etc/xdg/quickshell/noctalia-shell/shell.qml

$ qs -c noctalia-shell
An instance of this configuration is already running.
```

## 3. Ursache

Die exec-Zeile im Overlay startet Quickshell mit `-p` auf die **Datei** `shell.qml`
statt auf das **Verzeichnis**.

Im Dateimodus spannt Quickshell den QML-Importpfad nicht so auf wie im
Verzeichnismodus. Noctalias `shell.qml` importiert aber relativ aus `Commons`,
`Modules`, `Services`, `Widgets` und `Helpers`. Diese Imports scheitern, das
Root-Objekt entsteht nie — der Prozess lebt, belegt den Instanznamen und
zeichnet nichts.

**Manuell verifiziert:** `qs -p /etc/xdg/quickshell/noctalia-shell` startet die Shell korrekt.

> [!warning] Nachtrag vom Live-Test (25.08., ASUS X515JA)
> Beim Rollout-Test lief durch einen Bedienfehler (`bootc switch` auf eine
> bereits getrackte Referenz ist ein No-Op, siehe
> [[docs/06-lenovo-yoga-deployment#Umschalten]]) versehentlich noch der
> **alte** Build mit der Datei-Pfad-Exec-Zeile. Der ist auf einem frischen
> Reboot sauber gestartet (Journal: `Shell Noctalia Hello!`, Plugins
> geladen) — sichtbare Bar/Dock/Launcher, kein Absturz, keine leere Shell.
>
> Das stellt die obige Ursache als *alleinige* Erklärung für das
> ursprüngliche Symptom infrage. Der Verzeichnis-Modus bleibt die korrekte,
> offiziell empfohlene Variante und wurde inzwischen ebenfalls live
> verifiziert (siehe 4.1), aber der exakte Auslöser des allerersten
> Vorfalls (leere Shell, blockierter Instanzname) ist damit nicht
> zweifelsfrei reproduziert. Wahrscheinlicher als ein struktureller
> Datei-Modus-Bug: ein einmaliger Zustand, z. B. ein verwaister
> Quickshell-Prozess/Socket aus einer vorherigen abgebrochenen Session, der
> den Instanznamen blockiert hat, ohne dass ein neuer Prozess ihn
> übernehmen konnte. Falls das Symptom erneut auftritt: zuerst
> `pgrep -a qs` und `ls /run/user/*/quickshell/by-id/` auf Leichen prüfen,
> bevor wieder der Datei-vs-Verzeichnis-Pfad verdächtigt wird.

### Hintergrund zu Noctalia v4

`noctalia-shell` (v4-Linie) ist kein Programm, sondern ein QML-Baum. Gestartet
wird er über die Quickshell-Runtime `qs`, entweder per Verzeichnispfad (`-p`)
oder per Konfigurationsname (`-c`). Der Name-Modus sucht in
`$XDG_CONFIG_HOME/quickshell/<name>` und danach in jedem Eintrag von
`$XDG_CONFIG_DIRS` plus `/quickshell/<name>`; der Default `/etc/xdg` deckt den
RPM-Ablageort ab.

---

## 4. Zu erledigen

### 4.1 Pfad im Overlay korrigieren (Blocker)

Zeile lokalisieren — kann auch in einem `config.d`-Snippet stecken:

```bash
grep -rn "shell.qml" overlay/
```

Korrigieren:

```bash
sed -i 's|qs -p /etc/xdg/quickshell/noctalia-shell/shell.qml|qs -p /etc/xdg/quickshell/noctalia-shell|' \
  overlay/etc/sway/config
```

Erwogene Alternative: `exec qs -c noctalia-shell` (kürzer, übersteht einen Umzug
des QML-Baums, setzt aber ein `XDG_CONFIG_DIRS` voraus, das den Ablageort enthält).
Beim Verbleib in `/etc/xdg` funktioniert der Name-Modus ohne Zusatzarbeit.

### 4.2 Guard ins Containerfile

Hinter `COPY overlay/ /` einfügen:

```dockerfile
# Guard: qs -p muss auf das Verzeichnis zeigen, nie auf shell.qml --
# sonst startet der Prozess, scheitert an den relativen QML-Imports
# und blockiert stumm den Instanznamen.
RUN ! grep -rq "noctalia-shell/shell.qml" /usr/share/sway/ \
    && test -f /etc/xdg/quickshell/noctalia-shell/shell.qml
```

Der Grep zielt auf `/usr/share/sway/`, weil die exec-Zeile dort liegt
(`overlay/usr/share/sway/config.d/95-noctalia.conf`), nicht unter `/etc`.

Der bestehende Guard `RUN rpm -q noctalia-legacy` bleibt, deckt aber nur den
RPM-DB-Eintrag ab — nicht die Payload und nicht den Startpfad.

### 4.3 Optionale Abhängigkeiten prüfen — erledigt, kein Fix nötig

Prüfung im Container (`dnf history info 1` nach `dnf install -y
noctalia-shell`): dnf zieht Weak Dependencies standardweise mit
(`install_weak_deps` ist nirgends in `/etc/dnf/` deaktiviert). Ergebnis der
Transaktion:

| Programm | Quelle |
|---|---|
| `brightnessctl` | harte Abhängigkeit von `noctalia-shell` |
| `wlsunset`, `wl-copy`, `wpctl`, `nmcli` | bereits im Basisimage `sway-atomic:44` |
| `cava`, `cliphist`, `ddcutil` (+ `i2c-tools`), `matugen`, `gpu-screen-recorder`, `xrandr`, `lsb_release` | Weak Dependencies von `noctalia-shell`/Terra, automatisch von `dnf install noctalia-shell` mitgezogen |

Die im Abschnitt „Ausgangssymptom" vermutete Lücke besteht für den aktuellen
Terra-Paketstand nicht. Verifiziert per `command -v`/`rpm -qf` im gebauten
Image (`localhost/noctarow:44`) — alle acht geprüften Programme vorhanden,
keine manuelle Ergänzung im Containerfile nötig. Bei einem Terra-Update
erneut prüfen, falls sich die Paket-Metadaten ändern.

### 4.4 `/etc`-Merge beim Rollout beachten — Risiko geringer als vermutet, Check ergänzt

Die exec-Zeile steckte nie in `/etc/sway/config`, sondern in
`overlay/usr/share/sway/config.d/95-noctalia.conf` (siehe 4.1) — landet also
unter `/usr`, das bei jedem `bootc upgrade`/`switch` komplett ersetzt wird.
Der klassische Drei-Wege-Merge betrifft diese Datei **nicht**.

Restrisiko: Sway lädt `config.d`-Fragmente gestaffelt
(`/usr/share/sway/config.d/` → `/etc/sway/config.d/` → `$XDG_CONFIG_HOME/sway/config.d/`,
spätere Stufe gewinnt bei gleichem Dateinamen — siehe Kommentar in
`/etc/sway/config`). Falls auf einem Gerät während der Fehlersuche manuell
eine gleichnamige Datei unter `/etc/sway/config.d/95-noctalia.conf` angelegt
wurde (oder `/etc/sway/config` direkt editiert), überschreibt das weiterhin
lautlos den Image-Fix — das *ist* ein `/etc`-Fall und übersteht `bootc
upgrade`.

Check dafür jetzt in `scripts/noctarow.nu` als `noctarow etc-drift-check`
(auf dem Zielgerät ausführen, nicht im Image):

```bash
sudo ostree admin config-diff | grep sway
```

meldet lokale Abweichungen unter `/etc/sway` und weist explizit auf eine
kollidierende `95-noctalia.conf` hin, falls vorhanden.

---

## 5. Architektur-Empfehlung — umgesetzt

Der komplette QML-Baum (~500 Dateien) lag unter `/etc/xdg/quickshell/`. Auf
ostree bedeutet das: bei jedem `bootc switch` läuft der Drei-Wege-Merge über
alle Dateien. Wird lokal auch nur eine `.qml` geändert, gilt sie als
Admin-Modifikation und wird bei künftigen Updates nicht mehr ersetzt — Ergebnis
wäre ein QML-Baum aus zwei Versionen, der mit Import-Fehlern abbricht.

Umgesetzt: Baum nach `/usr` gespiegelt und von dort gestartet, direkt hinter
dem `rpm -q noctalia-shell`-Guard im `Containerfile`:

```dockerfile
RUN mkdir -p /usr/share/noctarow \
    && cp -a /etc/xdg/quickshell/noctalia-shell /usr/share/noctarow/noctalia-shell
```

`overlay/usr/share/sway/config.d/95-noctalia.conf` zeigt jetzt auf
`exec qs -p /usr/share/noctarow/noctalia-shell`. `/usr` ist read-only, der
Merge fasst es nicht an, jedes Image bringt garantiert einen konsistenten
Baum mit. Die RPM-Kopie in `/etc` bleibt liegen: `rpm -V` bleibt sauber, und
Azubis haben dort weiterhin einen Ansatzpunkt zum Experimentieren, ohne die
Flotte zu gefährden.

Passender Guard, hinter `COPY overlay/ /` neben dem Guard aus 4.2:

```dockerfile
RUN test -x /usr/bin/qs \
    && test -f /usr/share/noctarow/noctalia-shell/shell.qml
```

Mit dem Umzug greift auch der `noctarow etc-drift-check` aus 4.4 unverändert
weiter — der betrifft die Sway-Config, nicht den QML-Baum selbst.

## 6. Roadmap-Notiz: v4 → v5 — Upstream-Stand geprüft, Wechsel (noch) nicht empfohlen

Terra führt inzwischen Noctalia v5. Das läuft ohne Quickshell und ohne Qt direkt
auf Wayland/OpenGL ES und bringt ein echtes Binary mit. Die `/etc`-Problematik
aus Abschnitt 5 ist mit der `/usr`-Spiegelung bereits entschärft; ein Wechsel
würde zusätzlich den Qt-6.11-Upgrade-Zwang aus Terra entfallen lassen.

**Upstream-Stand geprüft** (`dnf repoquery --repo=terra "noctalia*"` im
gebauten Image):

| Paket | Version | Status |
|---|---|---|
| `noctalia` | `5.0.0~beta.9-1.fc44` | v5, **Beta** — noch keine stabile Release |
| `noctalia-greeter` | `1.2.1-2.fc44` | separates Login-Manager-Paket für v5 |
| `noctalia-legacy` | `4.7.7-2.fc44` | v4-Fortsetzung, siehe unten |
| `noctalia-shell` | `4.7.7-1.fc44` | auslaufender Alt-Name, siehe unten |

Empfehlung: **nicht jetzt wechseln.** `noctalia` steht noch auf `beta.9`,
und der Wechsel wäre keine reine Paketumbenennung, sondern ein
Architekturwechsel: kein Quickshell/`qs` mehr, vermutlich anderes
Config-Format, `noctalia-greeter` als zusätzliches Paket, und die
bestehenden `hosts/*/noctalia-settings.json` (v4-Format) müssten neu
verifiziert werden. Für eine Schulungsflotte ist das ein eigenes Vorhaben,
kein Nebeneffekt dieses Tickets. Vor einem Wechsel: Beta-Status erneut
prüfen, Config-Format-Migration der Host-Settings klären, Testgerät vor
Fleet-Rollout.

**Nebenbefund, bereits umgesetzt:** Terra hat die v4-Linie zwischenzeitlich
von `noctalia-shell` auf `noctalia-legacy` umbenannt — `noctalia-legacy`
obsoletet `noctalia-shell <= 4.7.7-1` und ist ein Release weiter
(`-2` vs. `-1`). Dateilayout (`/etc/xdg/quickshell/noctalia-shell/...`) und
Requires sind identisch, reines Rename. Containerfile installiert jetzt
`noctalia-legacy` statt des auslaufenden `noctalia-shell`-Alias, um auf der
aktiv gepflegten v4-Linie zu bleiben (verifiziert per Build, siehe
Commit-Historie).

---

## Nützliche Befehle

```bash
# Shell manuell starten (nur in laufender Wayland-Session)
qs -p /usr/share/noctarow/noctalia-shell     # Produktionspfad (Image)
qs -p /etc/xdg/quickshell/noctalia-shell     # RPM-Kopie, Azubi-Experimentierfläche
qs -c noctalia-shell

# Laufende Instanz inspizieren
pgrep -a qs
qs -c noctalia-shell log
journalctl --user -b | grep -iE "quickshell|noctalia" | tail -50

# Gezielt beenden
pkill -f "qs -p /usr/share/noctarow/noctalia-shell"

# Image ohne Registry-Fallback prüfen
podman run --rm --pull=never localhost/noctarow:44 bash -c '…'
```
