# Noctarow: Noctalia startet nicht — Diagnose & offene Aufgaben

**Projekt:** Noctarow (bootc-Image, Fedora Sway Atomic 44 + Noctalia + Homebrew-Toolchain)
**Repo-Artefakte:** `Containerfile`, `terra.repo`, `overlay/`
**Stand:** 2026-08-25 — Ursache gefunden und manuell verifiziert, Fix noch nicht im Image

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
RUN ! grep -rq "noctalia-shell/shell.qml" /etc/sway/ \
    && test -f /etc/xdg/quickshell/noctalia-shell/shell.qml
```

Der bestehende Guard `RUN rpm -q noctalia-shell` bleibt, deckt aber nur den
RPM-DB-Eintrag ab — nicht die Payload und nicht den Startpfad.

### 4.3 Optionale Abhängigkeiten prüfen

Terra empfiehlt für Noctalia Zusatzprogramme (u. a. `brightnessctl`, `cava`,
`wlsunset`), die `dnf install noctalia-shell` nicht mitzieht. Ohne sie startet
die Shell, einzelne Widgets bleiben aber leer. Für die Schulungsflotte
vermutlich mit ins Image aufnehmen. Konkrete Liste beim Start prüfen:

```bash
qs -c noctalia-shell 2>&1 | grep -i "not found"
```

### 4.4 `/etc`-Merge beim Rollout beachten

Auf Maschinen, auf denen die alte Session schon lief, kann `/etc/sway/config`
inzwischen als lokal modifiziert gelten. Dann greift der ostree-Drei-Wege-Merge
und die Korrektur kommt per `bootc switch` **nicht** an. Vor dem Flotten-Rollout
auf einem Testgerät prüfen:

```bash
ostree admin config-diff | grep sway
```

---

## 5. Architektur-Empfehlung (offen, nicht dringend)

Der komplette QML-Baum (~500 Dateien) liegt unter `/etc/xdg/quickshell/`. Auf
ostree bedeutet das: bei jedem `bootc switch` läuft der Drei-Wege-Merge über
alle Dateien. Wird lokal auch nur eine `.qml` geändert, gilt sie als
Admin-Modifikation und wird bei künftigen Updates nicht mehr ersetzt — Ergebnis
wäre ein QML-Baum aus zwei Versionen, der mit Import-Fehlern abbricht.

Vorschlag: Baum nach `/usr` spiegeln und von dort starten.

```dockerfile
RUN mkdir -p /usr/share/noctarow \
    && cp -a /etc/xdg/quickshell/noctalia-shell /usr/share/noctarow/noctalia-shell
```

Sway-Config dann auf `exec qs -p /usr/share/noctarow/noctalia-shell`.
`/usr` ist read-only, der Merge fasst es nicht an, jedes Image bringt garantiert
einen konsistenten Baum mit. Die RPM-Kopie in `/etc` bleibt liegen: `rpm -V`
bleibt sauber, und Azubis haben dort weiterhin einen Ansatzpunkt zum
Experimentieren, ohne die Flotte zu gefährden.

Passender Guard:

```dockerfile
RUN test -x /usr/bin/qs \
    && test -f /usr/share/noctarow/noctalia-shell/shell.qml
```

## 6. Roadmap-Notiz: v4 → v5

Terra führt inzwischen Noctalia v5. Das läuft ohne Quickshell und ohne Qt direkt
auf Wayland/OpenGL ES und bringt ein echtes Binary mit. Die v4-Schiene (aktuell
im Image, erkennbar am `noctalia-qs`/Qt-6.11-Kommentar im Containerfile) wird
upstream nicht mehr gepflegt. Ein Wechsel würde die gesamte `/etc`-Problematik
aus Abschnitt 5 erledigen und den Qt-6.11-Upgrade-Zwang aus Terra entfallen
lassen. Vor einem Wechsel: Upstream-Stand prüfen, das Paket heißt dort
inzwischen `noctalia` statt `noctalia-shell`.

---

## Nützliche Befehle

```bash
# Shell manuell starten (nur in laufender Wayland-Session)
qs -p /etc/xdg/quickshell/noctalia-shell
qs -c noctalia-shell

# Laufende Instanz inspizieren
pgrep -a qs
qs -c noctalia-shell log
journalctl --user -b | grep -iE "quickshell|noctalia" | tail -50

# Gezielt beenden
pkill -f "qs -p /etc/xdg/quickshell/noctalia-shell"

# Image ohne Registry-Fallback prüfen
podman run --rm --pull=never localhost/noctarow:44 bash -c '…'
```
