---
titel: Sway-Referenz — Fensterregeln, IPC, Nutzungsmodell
teil_von: "[[README]]"
tags: [sway, ipc, fensterregeln, drop-in, nushell, policy, barrierefreiheit, sprachsteuerung]
zielgeraet: [dozenten-pc, yoga920, flotte]
erstellt: 2026-08-07
status: entwurf
---

# 20 — Sway-Referenz: Fensterregeln, IPC, Nutzungsmodell

## 1 · Fensterkriterien

### Die beiden Direktiven

| Ziel | Direktive |
|---|---|
| Immer auf festem Workspace starten | `assign [app_id="…"] workspace number 3` |
| Immer floating auf dem aktuellen Workspace | `for_window [app_id="…"] floating enable` |

`assign` greift **bevor** das Fenster gemappt wird — kein Aufblitzen auf dem
falschen Workspace. Nachteil: nur Kriterien, die zum Map-Zeitpunkt bereits
feststehen (`app_id`, `class`, `instance`) — **nicht** `title`, das viele
Anwendungen erst später setzen.

Für titelbasierte Regeln stattdessen:

```
for_window [title="…"] move container to workspace number 3
```

> [!warning] Kriterien sind Regex mit Teiltreffer
> `[app_id="foot"]` trifft auch `footclient` und `barefoot`.
> **Immer mit `^…$` ankern.**

### Kriterien ermitteln — messen, nicht raten

```nu
def fenster-knoten [knoten: record] {
    let kinder = (($knoten.nodes? | default []) ++ ($knoten.floating_nodes? | default []))
    let selbst = (if ($knoten.pid? != null) {
        [{ name: $knoten.name?, app_id: $knoten.app_id?, class: $knoten.window_properties?.class? }]
    } else { [] })
    $selbst ++ ($kinder | each {|k| fenster-knoten $k } | flatten)
}

swaymsg -t get_tree | from json | fenster-knoten $in
```

`app_id: null` bedeutet **XWayland-Fenster** → dann `[class="…"]` statt
`[app_id="…"]` verwenden.

### Live testen ohne Reload

IPC-Befehle wirken sofort — Regeln lassen sich vor dem Festschreiben
ausprobieren:

```nu
swaymsg 'for_window [app_id="^org\.gnome\.Nautilus$"] floating enable, resize set 1280 800, move position center'
swaymsg 'assign [app_id="^md\.obsidian\.Obsidian$"] workspace number 3'
```

### Als Drop-in festschreiben

```nu
r##'# Fensterregeln
for_window [app_id="^org\.gnome\.Nautilus$"] floating enable, resize set 1280 800, move position center

assign [app_id="^md\.obsidian\.Obsidian$"] workspace number 3
assign [class="^Vmplayer$"]                workspace number 4
'## | sudo tee /etc/sway/config.d/40-fensterregeln.conf | ignore

swaymsg reload
```

> [!important] Drop-in-Konventionen
> - **Nummer bestimmt die Ladereihenfolge**, Dateiname ist Identität
> - `/etc/sway/config.d/` überschattet `/usr/share/sway/config.d/`
>   (verifiziert, siehe [[01-erkenntnisse]])
> - Fürs Image gehört die Datei via `COPY overlay/` nach
>   `/usr/share/sway/config.d/`; `/etc` bleibt maschinenspezifischen
>   Abweichungen vorbehalten

## 2 · Mehrfachstart und „run or raise"

Sway kennt kein eingebautes run-or-raise — der Baustein ist aber vorhanden:
**`focus` mit Kriterium wechselt automatisch auf den Workspace**, auf dem
das Fenster liegt.

```nu
swaymsg '[app_id="^org\.gnome\.Nautilus$"] focus'
```

### Variante A — run-or-raise in Nushell

Gehört als `export def` nach `scripts/noctarow.nu`, zusammen mit
`fenster-knoten`:

```nu
export def run-or-raise [muster: string, ...befehl: string] {
    let kriterium = $'[app_id="^($muster)$"]'
    let da = (
        swaymsg -t get_tree | from json | fenster-knoten $in
        | where {|f| ($f.app_id | default "") =~ $"^($muster)$" }
        | is-not-empty
    )
    if $da {
        swaymsg $"($kriterium) focus" | ignore
    } else {
        ^setsid --fork ...$befehl
    }
}
```

Bindung im Drop-in — `nu` kommt aus Homebrew, deshalb absoluter Pfad:

```
set $nu /home/linuxbrew/.linuxbrew/bin/nu
bindsym --to-code $mod+e exec $nu -c 'use /usr/libexec/noctarow/fenster.nu *; run-or-raise "org.gnome.Nautilus" nautilus'
```

> [!warning] Abhängigkeit vom Homebrew-Bootstrap
> Vor Abschluss von `homebrew-bootstrap.service` existiert `nu` nicht — die
> Taste tut dann nichts. Für Tastenbindungen im Basis-Image spricht das
> dafür, ein eigenständiges Skript mit Shebang unter
> `/usr/libexec/noctarow/` abzulegen (Muster wie `terminal-shell`).

### Variante B — harte Sperre über systemd

Ein `--unit`-Name ist systemweit eindeutig; der zweite Start scheitert
von selbst:

```nu
systemd-run --user --unit=app-nautilus --collect nautilus
```

Zweiter Aufruf → `Unit app-nautilus.service already exists`. Kein
Baum-Scan nötig, aber **der Fokus wechselt nicht mit**. Kombinierbar: erst
`swaymsg focus` versuchen, sonst `systemd-run`.

### Variante C — ohne Skript

Workspace-Wechsel **vor** dem Start; das Fenster öffnet dann auf dem
richtigen Workspace, ganz ohne `assign`:

```nu
swaymsg 'bindsym Mod1+o exec swaymsg "workspace number 3; exec obsidian"'
```

> [!tip] Vorher prüfen, ob überhaupt nötig
> Viele Programme sperren sich selbst (GApplication,
> Electron `requestSingleInstanceLock`):
> ```nu
> nautilus; sleep 2sec; swaymsg -t get_tree | from json | fenster-knoten $in | where app_id? =~ "Nautilus" | length
> ```
> Ergebnis `1` nach zwei Starts → run-or-raise dient nur noch dem
> Fokuswechsel.

## 3 · IPC als Programmierschnittstelle

Sways IPC ist ein vollwertiger Ereignisbus. Verfügbare Ereignisklassen:
`window`, `workspace`, `binding`, `mode`, `shutdown`, `tick`.

| Aufgabe | Befehl |
|---|---|
| Zustand abfragen | `swaymsg -t get_tree` |
| Ausgänge / Workspaces | `swaymsg -t get_outputs`, `-t get_workspaces` |
| Ereignisse abonnieren | `swaymsg -t subscribe -m '["window"]'` |
| Aktion auslösen | `swaymsg '[…] focus'` |

Das ist die Grundlage für alles dynamische Verhalten — statische
Konfiguration deckt den Rest ab.

> [!note] Bekannte Lücke
> Sway kann **benannte Regeln nicht zur Laufzeit an- und abschalten**.
> Dynamisches Verhalten wandert deshalb in den Ereignis-Daemon.

### Der Daemon `noctarowd`

Als systemd-User-Unit an `sway-session.target` gebunden — dasselbe Muster
wie beim Nextcloud-Autostart.

```nu
export def noctarowd [] {
    swaymsg -t subscribe -m '["window"]'
    | lines
    | each {|z|
        let e = ($z | from json)
        if $e.change == "new" {
            print $"neu: ($e.container.app_id?)"
        }
      }
}
```

> [!warning] Ungeprüft
> - Streamt `each` über einen unendlichen `subscribe`-Stream in Nushell
>   0.114.1 zuverlässig, ohne zu puffern?
> - Unit braucht `Restart=on-failure` und muss einen Sway-Neustart
>   überleben

## 4 · Konfiguration als Daten: `policy.nuon`

Die Fensterpolitik lebt compositor-neutral als NUON; ein Nushell-Renderer
erzeugt daraus die Drop-ins **zur Bauzeit**.

```
policy.nuon              ← eine Quelle
   └─ render-sway     → /usr/share/sway/config.d/*.conf
noctarowd.nu             ← nur fürs Dynamische
```

```nu
{
  profil: "senioren"
  regeln: [
    { name: "dateimanagement", match: { app_id: "org.gnome.Nautilus" }
      float: true, size: [1280 800], center: true }
    { name: "obsidian",        match: { app_id: "md.obsidian.Obsidian" }
      workspace: 3 }
  ]
  sprachbefehle: [
    { sagen: ["internet" "browser"] tun: "workspace number 1" }
    { sagen: ["dateien" "daten"]    tun: "exec nautilus" }
    { sagen: ["fenster zu"]         tun: "kill" }
  ]
}
```

Renderer-Kern:

```nu
export def render-sway [politik: record] {
    $politik.regeln | each {|r|
        let k = $'[app_id="^($r.match.app_id)$"]'
        let effekte = ([
            (if ($r.float?  | default false) { "floating enable" })
            (if ($r.size?   != null) { $"resize set ($r.size.0) ($r.size.1)" })
            (if ($r.center? | default false) { "move position center" })
        ] | compact | str join ", ")
        let zeilen = [
            (if ($effekte | is-not-empty) { $"for_window ($k) ($effekte)" })
            (if ($r.workspace? != null) { $"assign ($k) workspace number ($r.workspace)" })
        ]
        $zeilen | compact
    } | flatten | str join "\n"
}
```

> [!check] Abnahmekriterium
> Der Renderer gilt als tragfähig, wenn er aus `policy.nuon`
> **byte-gleiche** Dateien zu den handgeschriebenen Drop-ins erzeugt.

### Validierung zur Bauzeit

Sways Konfiguration ist Daten und damit im Containerfile prüfbar — Fehler
scheitern im Build, nicht auf dem Gerät vor der Klasse:

```bash
RUN sway --validate --config /etc/sway/config
```

## 5 · Nutzungsmodell für Einsteiger

### `tabbed` statt Fullscreen

Noctalias Bar und Dock sind **Layer-Surfaces** (`wlr-layer-shell`), keine
Fenster — sie liegen außerhalb des Bereichs, den Sway an Fenster verteilt.

| | Bar/Dock sichtbar? |
|---|---|
| `workspace_layout tabbed` | **ja** |
| `fullscreen` (Mod+f) | **nein** — überdeckt alle Layer |

„Alles füllt den Rest aus, Bar und Dock bleiben sichtbar" ist damit der
**Normalfall ohne Zusatzarbeit**, solange echtes Fullscreen nicht ausgelöst
wird. Die Reiterzeile macht offene Fenster außerdem sichtbar und klickbar —
ein sichtbares Modell statt unsichtbarer Zustände.

### Das Drop-in

```nu
r##'# Ein Fenster pro Bildschirm, sichtbar als Reiter
workspace_layout tabbed
default_border normal 1

# Vorhersagbarer Fokus
focus_follows_mouse no
mouse_warping none

# Dialoge schweben, alles andere nicht
for_window [window_type="dialog"] floating enable, move position center
for_window [app_id="^org\.gnome\.Nautilus$"] floating enable, resize set 1280 800, move position center

# Feste Plaetze: "Programm = Ort"
assign [app_id="^org\.mozilla\.firefox$"]   workspace number 1
assign [app_id="^libreoffice-.*$"]          workspace number 2
assign [app_id="^md\.obsidian\.Obsidian$"]  workspace number 3

# Fullscreen deaktivieren
bindsym --to-code $mod+f nop
'## | sudo tee /etc/sway/config.d/45-einsteiger.conf | ignore

swaymsg reload
```

### Clientseitiges Fullscreen zurücknehmen

Sway kennt kein „Fullscreen verbieten"; Videoplayer und
Präsentationsmodi fordern es selbst an. Weg über den Daemon:

```nu
swaymsg -t subscribe -m '["window"]'
| lines
| each {|z|
    let e = ($z | from json)
    if $e.change == "fullscreen_mode" and $e.container.fullscreen_mode > 0 {
        swaymsg $"[con_id=($e.container.id)] fullscreen disable" | ignore
    }
  }
```

Für Dozenten-Präsentationen bleibt echtes Fullscreen als **bewusste
Ausnahme** auf einer separaten, schwer versehentlich zu treffenden Bindung.

### Layer-Reservierung prüfen

Layer-Surfaces melden per `exclusive_zone`, wie viel Platz sie
beanspruchen:

```nu
swaymsg -t get_outputs    | from json | select name rect
swaymsg -t get_workspaces | from json | select name rect
```

Workspace-`rect` kleiner als Output (oben um Bar-, unten um Dock-Höhe) =
Reservierung stimmt. Identisch = Dock liegt über den Fenstern → Noctalia-
Einstellung prüfen oder `gaps outer`.

### Fedora-Defaults entschärfen

Drei Einsteiger-Fallen aus `sway-config-fedora` überschreiben
(`bindsym … nop` bzw. aus dem eigenen `set $mod`-Block heraushalten):

- **Resize-Submap** — Modus ohne sichtbaren Ausweg
- **`Mod+Shift+e`** — beendet die Session
- **`Mod+Shift+q`** — direkt neben `Mod+q`

> [!note] Pädagogische Leitplanke
> Neue Erfahrung im **Verhalten** (feste Orte, keine verlorenen Fenster,
> nichts zu konfigurieren), vertraute Erfahrung in den **Gesten**
> (Alt+Tab wechselt Reiter, Klick fokussiert, Titel mit Schließen-Symbol).

## 6 · Alte Hardware

### Renderer

Sway/wlroots kann über `WLR_RENDERER=pixman` **rein auf der CPU** rendern —
im Projekt bereits unter WSLg und Hyper-V im Einsatz (siehe
[[14-xps13-wslg-sway-nushell-runde1]], [[03-bauen-und-testen]]).

Sway 1.12 verweigert den Start auf „nicht unterstützten" GPUs nicht mehr,
sondern gibt nur noch einen Hinweis aus.

### GPU-Fähigkeiten pro Gerät ermitteln

```nu
sudo dnf install glx-utils egl-utils mesa-demos
lspci | find -i vga
eglinfo -B | lines | find -i "OpenGL ES profile version"
glxinfo | lines | find -i "OpenGL renderer"
```

### Ressourcenbedarf

```nu
ps -l | where name =~ '(?i)sway' | select pid name cpu mem virtual
```

Größenordnung: **~40–90 MB RSS**. Der große Hebel auf schwachen Maschinen
ist, dass **kein vollständiger Desktop (GNOME/KDE)** läuft — nicht die
Feinabstimmung des Compositors.

## 7 · Projektgesundheit

Stand aus der Recherche, **mit Datum zu versehen und jährlich zu prüfen**:

- **Sway 1.12** erschien am 25. Mai 2026, knapp ein Jahr nach 1.11 —
  138 Änderungen von 50 Beitragenden, auf Basis von **wlroots 0.20**
- Inhalte: HDR10 über den Vulkan-Renderer, Einzelfenster-Aufnahme,
  `color-management-v1`, `ext-workspace-v1`, `xdg-toplevel-tag-v1`
- `xdg_session_management_v1` hat es **nicht** in diese Runde geschafft
- Fundament ist **wlroots**, das auch labwc, river, Wayfire und phosh
  trägt; gepflegt seit 2020 von Simon Ser, zugleich zentraler
  Wayland-Protokoll-Maintainer
- Sway Atomic ist ein **offizieller Fedora-Spin** — die Kette
  (`sway-config-fedora`, `sway-session.target`, Basis-Image
  `sway-atomic:44`) hängt an Fedoras Release-Engineering

> [!important] Konfigurationsstabilität als Flottenargument
> Die Konfigurationssprache ist durch den i3-Kompatibilitätsvertrag
> praktisch eingefroren. Der `render-sway`-Ausgabetext bleibt damit
> voraussichtlich über Jahre gültig — für eine Schulungsflotte der
> entscheidende Punkt.

> [!note] Frühwarnsignale
> Nicht Release-Abstände beobachten, sondern: wlroots-Releases bleiben
> länger als ein Jahr aus · Fedora stuft den Sway-Spin auf
> „Community-maintained" zurück · neue Protokolle bleiben über mehrere
> Zyklen liegen. Ein jährlicher Blick in die Release Notes genügt.

## 8 · Sprachsteuerung

**Machbarkeit ist geklärt: Sway ist an keiner Stelle das Hindernis.**

| Baustein | Von Sway abhängig? |
|---|---|
| Mikrofon, Audioaufnahme | nein (PipeWire) |
| Spracherkennung | nein (eigener Prozess) |
| Befehle ausführen | ja — `swaymsg`, vorhanden |
| Text in Anwendungen tippen | ja — `virtual-keyboard-v1`, unterstützt |

Zwei getrennte Probleme:

- **Befehlssteuerung** — leicht. Braucht *keine* Eingabesimulation und
  umgeht damit Waylands Sicherheitsmodell vollständig: Spracherkennung →
  `swaymsg 'workspace number 2'`. Derselbe Kanal wie `noctarowd`; Sprache
  ist einfach eine weitere Ereignisquelle.
- **Diktat** — schwer. `wtype` über `virtual-keyboard-v1`, oder
  `dotool`/`ydotool` über `/dev/uinput` (braucht udev-Regel für die Gruppe
  `input` — eine bewusste Rechteentscheidung, die ins Image gehört).

Engine-Empfehlung für alte Hardware: **Vosk** statt Whisper — leichtgewichtig,
und mit **fester Wortliste** einschränkbar. Bei 20 Befehlen statt 100 000
Wörtern steigt die Trefferquote deutlich und die CPU-Last fällt. Deutsches
Kleinmodell `vosk-model-small-de-0.15` (~45 MB).

```nu
def sprachbefehl [text: string, politik: record] {
    let treffer = ($politik.sprachbefehle | where {|b| $b.sagen | any {|s| $text =~ $s} })
    if ($treffer | is-not-empty) {
        swaymsg ($treffer | first | get tun) | ignore
    }
}
```

Die Vosk-Anbindung braucht Python (`vosk-api`) — die einzige Stelle, an der
die Nushell-Kette bricht. Als kleiner Prozess, der erkannte Zeilen auf
stdout schreibt, bleibt die Trennung sauber.

> [!warning] Drei Punkte, die im Klassenraum entscheiden
> **Akustik** — ein Kleinmodell in einem Raum mit 20 Personen ist etwas
> anderes als am ruhigen Schreibtisch; ohne Headset oder Richtmikrofon wird
> das nichts. Hardware-Posten, kein Softwareproblem.
> **Push-to-talk statt Dauerlauschen** — ein permanent offenes Mikrofon in
> einer Ausbildungseinrichtung ist eine Governance-Frage.
> **DSGVO** — der lokale Ansatz ist hier das Hauptargument, nicht ein
> Nebeneffekt. Kein Cloud-STT, dokumentiert.

Hardware-Aufrüstung ist damit **kein Muss, sondern ein Qualitätshebel**:
klein anfangen mit Vosk, später Whisper — ohne Architekturänderung.

## 9 · Zugänglichkeit

Details in [[17-zugaenglichkeitsprofil-senioren]]; hier nur die
Sway-spezifische Substanz.

**Der größte Teil liegt nicht im Compositor.** GTK und Qt legen ihren
Bedienbaum über AT-SPI auf dem D-Bus offen — unabhängig vom Compositor.
Auf Sway ist dieser Baum bereits vorhanden. Im Newton-Modell schrumpft die
Compositor-Rolle weiter: Der Compositor verarbeitet die
Accessibility-Baum-Updates nicht, er reicht sie nur durch.

Lücken auf Sway, nach Aufwand sortiert:

| Lücke | Aufwand | Wo |
|---|---|---|
| Compositor-Zustand wird nicht angesagt | **klein** | außerhalb von Sway |
| Kontrast, Schriftgrößen, Cursor, Tastaturbedienung | klein | Konfiguration |
| Globale Tastengriffe für Screenreader | groß | in Sway, upstream |
| Bildschirmlupe | groß | wlroots-Szenengraph |
| Newton-Protokoll durchreichen | mittel | wlroots/Sway |

> [!tip] Wo Sway strukturell im Vorteil ist
> Der komplette Fensterbaum liegt als JSON auf der IPC. Eine Brücke von
> `swaymsg -t subscribe` zu `piper` oder `espeak-ng` — „Arbeitsfläche zwei,
> Firefox" — ist Tage Arbeit, kein Projekt. Sie lebt in `noctarowd`,
> braucht keine Upstream-Zustimmung.

Empirischer Einstieg statt Vermutung:

```nu
sudo dnf install orca
$env.QT_ACCESSIBILITY = 1
orca --replace &
# Nautilus, LibreOffice, Firefox oeffnen und protokollieren,
# was angesagt wird und was stumm bleibt
```

> [!warning] Zwei Vorbehalte vor Entwicklungsarbeit
> **Der Boden bewegt sich** — Newton (AccessKit) soll AT-SPI durch ein
> Wayland-natives Protokoll ersetzen; eigener Wissensstand dazu ist von
> 2024 und vor jeder Entscheidung neu zu prüfen. Auf den alten Stack zu
> bauen, während der neue entsteht, wäre der teure Fehler.
> **Upstream ist eine politische Frage** — compositor-seitige Änderungen
> (globale Grabs, Lupe) müssen angenommen werden. Sway ist bewusst
> minimalistisch; ein Patch kann fachlich gut und trotzdem unerwünscht
> sein. Kalkuliere die Möglichkeit ein, die Arbeit dauerhaft als Fork oder
> Patch-Layer im Image zu tragen.

## 10 · Offene Messpunkte

- [ ] Entfernt `default_border none` die tabbed-Reiterzeile?
      (deshalb vorerst `normal 1`)
- [ ] Greift `window_type="dialog"` unter Wayland, oder ist es ein
      X11-Erbe? Sonst `app_id` + Titel je Anwendung
- [ ] Puffert `each` über einen `swaymsg -t subscribe`-Stream in
      Nushell 0.114.1?
- [ ] `exclusive_zone` von Noctalia-Bar und -Dock verifizieren
- [ ] `eglinfo -B` auf allen Flottengeräten — GLES-Version dokumentieren
- [ ] `render-sway`: byte-gleich zu den Hand-Drop-ins?
- [ ] `noctarowd` als User-Unit — übersteht Sway-Neustart?
- [ ] Vosk-Erkennungsrate für die zehn wichtigsten Befehle unter
      Realbedingungen, mit und ohne Wortlisten-Einschränkung
- [ ] Orca-Lückenliste erheben
- [ ] Nutzerbeobachtung: Wird die Reiterzeile als klickbar erkannt?
