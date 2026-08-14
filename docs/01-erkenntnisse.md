---
titel: Erkenntnisse — Wie Fedora Sway konfiguriert wird
teil_von: "[[README]]"
tags:
  - sway
  - fedora
  - keyboard
  - xkb
  - layering
  - dnf
  - terra
  - packaging
verifiziert_am: 2026-07-17
verifiziert_gegen: quay.io/fedora-ostree-desktops/sway-atomic:44 (aarch64, x86_64)
---

# 01 — Erkenntnisse

Alles hier wurde gegen das echte Image verifiziert, nicht aus Dokumentation
abgeleitet.

## Das dreistufige Include-System

Die Hauptkonfiguration `/etc/sway/config` enthält in Zeile 228 genau eine
Include-Direktive:

```
include '$(/usr/libexec/sway/layered-include \
    "/usr/share/sway/config.d/*.conf" \
    "/etc/sway/config.d/*.conf" \
    "${XDG_CONFIG_HOME:-$HOME/.config}/sway/config.d/*.conf")'
```

`layered-include` ist ein Python-Skript aus dem Paket `sway-systemd`. Es
sammelt alle Treffer in ein Dictionary mit dem **Basename als Schlüssel** und
schreibt anschließend `sorted(configs)` als Include-Liste in eine temporäre
Datei unter `$XDG_RUNTIME_DIR/sway/`.

> [!important] Zwei Mechanismen, die man leicht verwechselt
> - **Dateiname = Identität.** Gleicher Name in einer höheren Ebene ⇒ die
>   Datei der niedrigeren Ebene wird *gar nicht* geladen.
> - **Nummernpräfix = Ladereihenfolge.** Alphabetisch, ebenenübergreifend.

Die drei Ebenen, in aufsteigender Priorität:

| Ebene | Pfad | Zuständigkeit | bootc |
|---|---|---|---|
| 1 | `/usr/share/sway/config.d/` | Image-Defaults | read-only, sauber ersetzt |
| 2 | `/etc/sway/config.d/` | lokale Administration | 3-Wege-Merge |
| 3 | `~/.config/sway/config.d/` | Benutzer | Home |

> [!tip] Konsequenz für den Image-Bau
> Eigene Defaults gehören nach **`/usr/share`**, nicht nach `/etc`.
> `/usr` wird bei jedem Image-Update deterministisch ersetzt; `/etc` bleibt
> damit frei für maschinenspezifische Abweichungen — genau die Trennung, die
> eine Schulungsflotte braucht.

## Auslieferungszustand des Images

`/usr/share/sway/config.d/`:

```
50-rules-browser.conf          60-bindings-volume.conf
50-rules-pavucontrol.conf      65-mode-passthrough.conf
50-rules-policykit-agent.conf  90-bar.conf
60-bindings-brightness.conf    90-swayidle.conf
60-bindings-media.conf         95-autostart-policykit-agent.conf
60-bindings-screenshot.conf    95-xdg-desktop-autostart.conf
                               95-xdg-user-dirs.conf
```

`/etc/sway/config.d/`:

```
10-systemd-cgroups.conf
10-systemd-session.conf
```

Beide `10-*`-Dateien stammen aus `sway-systemd` und werden vom RPM nach `/etc`
installiert. Auf bootc kommen sie aus `/usr/etc` und unterliegen dem
3-Wege-Merge. **Nicht anfassen.**

## Das Tastaturproblem — endgültige Diagnose

Drei Befunde zusammen ergeben ein eindeutiges Bild:

1. **Keine der 13 Dateien setzt einen `input`-Block.** Kein `xkb_layout`,
   nirgends.
2. **Kein Aufruf von `locale1-xkb-config`.** Die Brücke zwischen
   `org.freedesktop.locale1` (also `localectl`) und Sway wird nicht gebaut.
3. **`/etc/sway/config.live.d/` existiert im Image nicht.** Das Paket
   `sway-config-fedora` liefert dort eine Datei, die in der Live-Umgebung das
   Systemlayout übernimmt. Im installierten System gibt es das Verzeichnis
   nicht.

**Sway bekommt das im Installer gewählte Layout also schlicht nie zu sehen.**

Das betrifft Spin und Atomic gleichermaßen — es ist kein Atomic-spezifischer
Bug. Upstream läuft dazu ein Merge Request gegen `sway-config-fedora`, der die
Live-Datei in die Default-Konfiguration übernimmt.

### Zwei Lösungswege

**Statisches Drop-in** (gewählt): eine Datei mit `input`-Block ins Image.
Deterministisch, keine Laufzeitabhängigkeit, funktioniert auch im Container.

**Dynamische Brücke via locale1**: `sway-systemd` bringt ein Skript mit, das
die `localectl`-Einstellungen per D-Bus abfragt und via `swaymsg` anwendet.

```bash
rpm -ql sway-systemd | grep -i locale1
```

Damit wird `localectl` zur Single Source of Truth. Preis: läuft nur mit
laufendem `systemd-localed`, also **nicht im nested Container testbar**.

> [!warning] Für eine Schulungsflotte
> Der statische Weg ist vorzuziehen. Die Hardware ist bekannt, das Layout ist
> bekannt, und eine Laufzeitabhängigkeit weniger heißt ein Fehlerbild weniger
> vor 20 Auszubildenden.

## Kollisionen mit Noctalia

| Datei | Problem | Lösung |
|---|---|---|
| `90-bar.conf` | startet `swaybar` parallel zu Noctalias Panel | gleichnamige Leerdatei |
| `90-swayidle.conf` | zweiter Idle-Daemon, streitet um die Sperre | gleichnamige Leerdatei |

Weil wir das Image selbst bauen, überschreiben wir die Dateien direkt in
`/usr/share` — kein `/etc`-Umweg, kein Merge-Risiko.

## Fremdrepos: `Obsoletes` ersetzt Pakete lautlos

**Befund:** `dnf install -y noctalia-shell nushell helix` lief mit Exit-Code 0
durch. `noctalia-shell` und `helix` waren im Image, `nushell` nicht. Kein
Fehler, keine Warnung.

Ursache steht im Build-Log, im `Installing:`-Block — drei angeforderte Pakete,
aber an nushells Stelle ein Fremdkörper:

​```
Installing:
 helix               x86_64 0:25.07.1-11.fc44   updates     19.2 MiB
 noctalia-shell      x86_64 0:4.7.7-1.fc44      terra       32.1 MiB
 terra-obsolete      noarch 0:44-7              terra        0.0   B
​```

`terra-obsolete` deklariert:

​```
nushell < 0.101.0-3
​```

Fedora 44 liefert `nushell-0.99.1`. Die Bedingung trifft zu, also ersetzt dnf
das angeforderte Paket durch den Obsoleter — **wortlos, mit Exit-Code 0.**

> [!danger] Ein erfolgreicher Build ist kein Beweis, dass ein Paket drin ist
> Das gilt für **jedes** Fremdrepo, nicht nur Terra. `skip_if_unavailable=False`
> schützt nicht davor: das Repo *war* erreichbar, das Paket *war* auflösbar.
> Konsequenz: nach jedem Build gegen die Liste der angeforderten Pakete prüfen.
> ​```nu
> podman run --rm localhost/noctarow:44 rpm -q nushell noctalia-shell helix
> ​```

### Diagnose-Reihenfolge

Sie hat funktioniert und ist übertragbar:

1. `bootc status` — läuft überhaupt das fragliche Image? (hier: ja)
2. `podman history --no-trunc` — steht das Paket in der ausgeführten RUN-Zeile?
   (hier: ja)
3. `podman run --rm <image> rpm -q <paket>` — Image-Inhalt statt Host-Zustand
4. `podman build --no-cache` + Log lesen — der `Installing:`-Block ist die
   Wahrheit, nicht der Exit-Code
5. `rpm -q --obsoletes <verdächtiger>` — der Beweis

### Dritte bewusste Abweichung in `terra.repo`

​```ini
excludepkgs=terra-obsolete
​```

`terra-obsolete` stand unter `Installing:`, **nicht** unter
`Installing dependencies:` — kein Terra-Paket verlangt es. Sein Zweck ist,
Terras eigene Pakete zurückzuziehen, sobald Fedora sie führt; in einem
From-Scratch-Image gibt es nichts zu migrieren.

> [!note] Upstream-Bug, kein Konfigurationsfehler
> Die Versionsgrenze müsste *unterhalb* der Fedora-Version liegen. Bei
> `0.101.0-3` gegen Fedoras `0.99.1` frisst sie Fedoras Paket. Bei Fyra Labs
> zu melden; die Zeile ist entfernbar, sobald es korrigiert ist. Genau dafür
> ist `terra.repo` gevendort.

> [!warning] Gleiche Falle wartet bei `uutils-coreutils-util-linux`
> `terra-obsolete` obsoletet es ebenfalls (`< 0.0.29-2`). Relevant, falls
> Noctarow das je aufnimmt.

**Verifiziert am 2026-07-17** gegen `sway-atomic:44` (x86_64, Yoga 920):
`nushell-0.99.1-4.fc44.x86_64` installiert, `terra-obsolete` nicht installiert,
`/usr/bin/nu` vorhanden.
## Der Login-Screen ist ein separates Problem

Im Image liegt `/etc/sway/sddm-greeter.config`. **SDDM ist der
Display-Manager.** Ein Sway-Drop-in wirkt erst *nach* dem Login. Die Tastatur
im Login-Screen kommt aus `/etc/vconsole.conf` und der SDDM-Greeter-Umgebung.

Behandelt in [[docs/05-hidpi-und-monitore]].

## Was der nested Container *nicht* testen kann

- `10-systemd-session.conf` läuft ins Leere → Fehlermeldungen zu
  `sway-session.target` sind **erwartet**
- `95-xdg-desktop-autostart.conf` bleibt wirkungslos
- der `locale1`-Brückenpfad (kein `systemd-localed`)
- das `/etc`-3-Wege-Merge-Verhalten über zwei Image-Generationen
- SDDM, First-Boot-tmpfiles ins `$HOME`

Dafür bleibt nur der echte `bootc switch` auf dem Yoga selbst, siehe
[[docs/06-lenovo-yoga-deployment]] — eine separate VM-Teststufe entfällt, da
Build- und Zielmaschine identisch sind.

> [!note] Offene Punkte, nicht vergessen
>
> - **Lint-Warnungen:** `nonempty-run-tmp` (`/run/dnf`) und `var-log` (`/var/log/dnf5.log`) überleben dein `rm -rf`. Kosmetisch, aber `rm -rf /run/dnf /var/log/dnf5.log /var/lib/dnf` im selben RUN räumt sie weg.