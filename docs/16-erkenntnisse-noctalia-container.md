---
titel: Erkenntnisse — Noctalia, Container, Nushell (Session 2026-07-16)
aliases: [Erkenntnisse Noctalia, Session-Erkenntnisse Container]
teil_von: "[[README]]"
tags: [erkenntnisse, noctalia, quickshell, noctalia-qs, terra, sway, capabilities, bootc, podman, nushell]
erstellt: 2026-07-16
system: Fedora Sway Atomic 44 (Yoga 920-13IKB, x86_64)
verifiziert_am: 2026-07-16
verifiziert_gegen: quay.io/fedora-ostree-desktops/sway-atomic:44 (x86_64), noctalia-shell 4.7.7 / noctalia-qs 0.0.12
status: im-container-verifiziert
---

# 16 — Erkenntnisse: Noctalia, Container, Nushell

> [!info] Zweck & Abgrenzung
> Fortschreibung von [[docs/01-erkenntnisse]] um die Befunde aus dem
> ersten Noctalia-Image-Durchlauf auf dem Yoga (x86_64). `01` ist gegen
> aarch64/WSL verifiziert; diese Note ergänzt x86_64-native und
> Noctalia-spezifische Erkenntnisse. Der Ablauf und das Containerfile stehen in
> [[Noctalia im Noctarow-Image – Containerfile und Ablauf]].

> [!warning] Numerierungskollision
> Die Containerfile-Note wurde versehentlich als `11` angelegt — `11` ist aber
> [[docs/11-kvm-windows11-vm]]. Vorschlag: Containerfile-Note → `15`, diese Note
> → `16`. Dateinamen entsprechend anpassen.

## Noctalia & quickshell

### `noctalia-qs` kollidiert mit Fedoras `quickshell`

Noctalia v4 nutzt einen eigenen Quickshell-Fork `noctalia-qs` (gleiche Provides
wie `quickshell`, **nicht gleichzeitig** installierbar). Das offizielle Paket
`noctalia-shell` liegt in **Terra** und zieht `noctalia-qs` + Deps. Terra baut
für x86_64 **und** aarch64.

> [!important] Korrektur an einer früheren Annahme
> `quickshell` liegt „in offiziellen Fedora-Repos". Das stimmt für
> Quickshell allgemein — aber **für Noctalia v4 nicht nutzbar**, weil der Fork
> gebraucht wird und mit dem Fedora-Paket kollidiert. Für Noctarow: `noctalia-qs`
> via Terra, **kein** `quickshell` installieren.

### Sway-Workspace-Backend ist in v4.7.x real

`SwayService.qml` (i3-IPC via `Quickshell.I3`) existiert ab v4.7.x; das
Bar-Widget zieht `CompositorService.workspaces` compositor-agnostisch und ruft
`switchToWorkspace()`. Die Doku-Zeile „nur Niri und Hyprland" ist veraltet.

> [!check] Doppelt verifiziert
> Aus dem v4.7.7-Quellcode **und** live im nested Test:
> `INFO qml: SwayService Service started`. Nicht der `ext-workspace`-Fallback,
> sondern das dedizierte i3-Backend.

### `qs -c noctalia-shell` funktioniert mit dem Terra-Paket nicht

`noctalia-qs 0.0.12` sucht die Config in `/usr/share/quickshell` (Data-Pfad)
statt in `/etc/xdg/quickshell` (Config-Pfad), wo `shell.qml` korrekt liegt.
`HOME` und `XDG_CONFIG_DIRS` zu setzen ändert nichts.

**Lösung:** Pfad explizit setzen, Namensauflösung umgehen.

```ini
exec qs -p /etc/xdg/quickshell/noctalia-shell/shell.qml
```

> [!tip] `-p` ist die bessere Wahl, nicht nur ein Workaround
> Im selbstgebauten Image kennst du den Pfad. `-p` hängt weder von quickshells
> Suchreihenfolge noch vom Fork-Verhalten ab und übersteht eine v5-Migration.
> Der `Shell ID`-Hash ist pfadbasiert — mit `-c` käme derselbe heraus, `-p`
> verschiebt also **nicht**, wo Noctalia Daten ablegt.

## Config-Layout, Versions-Gate und Theming (aus der Wegwerf-Layer-Exploration)

> [!info] Herkunft
> Diese drei Punkte stammen aus dem ersten Wegwerf-Layer-Test auf dem laufenden
> System (`rpm-ostree install`, vor dem Container-Durchlauf) und sind hier
> zusammengeführt, weil dieser Foliensatz nicht neu erstellt werden musste —
> lediglich die Config-Pfade unten sind mit `noctalia-qs 0.0.12` (s. u.) leicht
> präzisiert.

### Nushell-Versions-Gate für den Sway-Workspace-Backend

Der Sway-Workspace-Backend kam erst im Laufe der v4-Serie dazu. Maßgeblich ist
die **Paketversion** von `noctalia-shell`, nicht `qs --version` (das liefert
die Version des `noctalia-qs`-Runtimes):

```nu
let ver = (rpm -q --queryformat '%{VERSION}' noctalia-shell)
let parts = ($ver | split row '.')
let major = ($parts | get 0 | into int)
let minor = ($parts | get 1 | into int)

if $major == 4 and $minor >= 7 {
    print $"Noctalia ($ver) – Sway-Workspace-Backend vorhanden ✓"
} else {
    print $"Noctalia ($ver) – zu alt für Sway-Workspaces, bitte aktualisieren"
}
```

### Config-Pfade

| Zweck | Pfad |
|---|---|
| Shell-QML (aus Terra-Paket, system-weit) | `/etc/xdg/quickshell/noctalia-shell/` |
| Deine Settings (JSON, von der Shell geschrieben) | `~/.config/noctalia/` |
| Cache / Wallpaper etc. | `~/.cache/noctalia/` |

Konfiguriert wird primär über das Settings-Panel in der laufenden Shell (nicht
durch Handeditieren) — es schreibt nach `~/.config/noctalia/`. Zum Start des
QML-Pfads selbst siehe oben, [„`qs -c noctalia-shell` funktioniert mit dem
Terra-Paket nicht"](#qs--c-noctalia-shell-funktioniert-mit-dem-terra-paket-nicht) —
`-p /etc/xdg/quickshell/noctalia-shell/shell.qml` ist der verifizierte Weg.

### Theming-Env (qt6ct/Kvantum-Kontext)

Für konsistentes Icon-/Theming-Verhalten sind zwei Env-Variablen relevant.
Für die Exploration reicht ein temporäres Setzen via `with-env`; fürs Image
gehören sie system-weit in `sway/environment.noctarow`:

```nu
with-env { QT_QPA_PLATFORMTHEME: gtk3 } { qs -c noctalia-shell }
```

Icon-Theme danach mit `nwg-look` wählen. Der Quickshell-IPC-Quirk erlaubt
zudem `QT_QPA_PLATFORM=wayland;xcb` (IPC-Calls funktionieren damit korrekt).

> [!note] Noch nicht gegen den Container verifiziert
> Diese Env-Variablen stammen aus dem Wegwerf-Layer-Test auf dem laufenden
> System, nicht aus dem nested Container. Vor Aufnahme ins Image gegenprüfen.

## Sway auf Fedora Atomic

### Fedoras sway trägt `cap_sys_nice=ep`

`getcap /usr/bin/sway` → `cap_sys_nice=ep`. In einem Container mit Podmans
Default-Caps scheitert der Start:

```
exec container process `/usr/sbin/sway`: Operation not permitted
```

Beim `execve` gilt `pP' = (X & fP) | (pI & fI)`; fehlt `SYS_NICE` im Bounding
Set X, bekommt der Prozess die permitted-Caps der Datei nicht und der Kernel
bricht mit `EPERM` ab. Podmans Default hat `SYS_NICE` **nicht**.

**Fix:** `--cap-add=SYS_NICE`. Betrifft rootless wie rootful, mit und ohne
`keep-id`. bash läuft, weil es keine File-Caps hat.

> [!important] Der Cap gehört ins Image, nicht raus
> `cap_sys_nice` erlaubt sway Echtzeit-Priorität — auf echter Hardware gewollt.
> **Kein `setcap -r`.** Das Problem ist die Container-Laufzeit, nicht das Image.

### `/usr/share/sway/environment` existiert bei Fedora nicht

Env-Variablen werden an **`/etc/sway/environment`** angehängt (Shell-Skript,
`ft=sh`, von `/usr/bin/start-sway` gesourct). Ein `COPY … /usr/share/sway/
environment` legt eine Datei an, die **niemand liest**.

> [!important] Korrektur an [[docs/09-yoga-buildumgebung]]
> Das Zwischenstands-Containerfile hatte `COPY … /usr/share/sway/environment`.
> Falsch. Richtig: **anhängen** an `/etc/sway/environment`, sonst verschwindet
> Fedoras `_JAVA_AWT_WM_NONREPARENTING=1`.
> ```dockerfile
> COPY sway/environment.noctarow /tmp/environment.noctarow
> RUN cat /tmp/environment.noctarow >> /etc/sway/environment && rm /tmp/environment.noctarow
> ```

Ebenfalls nicht vorhanden: `/usr/share/sway/config` — Hauptconfig ist
`/etc/sway/config`. Das Verzeichnis `/usr/share/sway/config.d/` existiert (siehe
[[docs/01-erkenntnisse#Das dreistufige Include-System]]).

### Die Statuszeile: swaybar oder waybar — noch offen

> [!warning] Ich hatte mich hier zu früh festgelegt
> In früheren Notizen dieser Session habe ich behauptet, Fedoras Leiste sei
> **waybar** und [[docs/01-erkenntnisse#Kollisionen mit Noctalia]] („startet
> swaybar") sei zu korrigieren. **Das ist nicht belegt.** `01` ist gegen das
> echte Image verifiziert; mein „waybar" stammte aus einer Websuche, die den
> Spin statt Atomic gemeint haben kann. Beleg fehlt in beide Richtungen.
>
> Indiz für waybar: `swaymsg bar mode invisible` wirkte beim Nutzer nicht — das
> spräche gegen einen swaybar-`bar {}`-Block. Indiz für swaybar: die verifizierte
> `01`. **Ungeklärt.** Settelt sich mit einem Befehl:
> ```nu
> noctarow test-nested --tag 44 --shell
> # im Container:
> cat /usr/share/sway/config.d/90-bar.conf
> pgrep -al waybar
> ```
> `exec waybar` → waybar (01 korrigieren). `bar { … }` → swaybar (meine
> waybar-Behauptung korrigieren).

> [!check] Der Fix funktioniert unabhängig davon
> Wir **ersetzen** `/usr/share/sway/config.d/90-bar.conf` im Build durch eine
> leere Datei gleichen Namens — dann startet keine der beiden Leisten, egal
> welche es war. Die swaybar/waybar-Frage ist also nur ein
> Dokumentations-Genauigkeitspunkt, kein Funktionsrisiko. Gleiches gilt für
> `90-swayidle.conf`.

### Verwaister `nmcli monitor` hält abgemeldete Session offen

Nach einem Sway-Logout (Session 2 → 6, 2026-08-14) blieb `session-2.scope` im
Zustand `active (abandoned)` haengen, obwohl der Sway-Leader-Prozess bereits
tot war. Ursache: `/usr/bin/nmcli -t monitor` (PPID → 1, verwaist) lief in der
Cgroup weiter und hielt sie dadurch nicht leer. `loginctl terminate-session`
raeumte die Session deswegen nicht auf; erst `kill` auf die Waisen-PID leerte
die Cgroup, danach hat systemd/logind Scope und Session sofort entfernt.

> [!note] Reproduziert (2026-08-14, zweiter Logout/Login-Zyklus)
> Gleiches Muster erneut aufgetreten: nach Ab-/Anmelden blieb `session-6.scope`
> im Zustand `closing` haengen, `cgroup.procs` der Scope enthielt nur noch die
> verwaiste `nmcli -t monitor`-PID (PPID 1). Damit kein Einzelfall mehr,
> sondern reproduzierbar bei Sway-Logout. Offen: welches Widget `nmcli monitor`
> startet und warum es bei `Compositor Logout requested` nicht mitbeendet wird.

## bootc / rpm-ostree / podman

### Qt 6.11: nur beim Layering ein Problem

`noctalia-qs` braucht `libQt6Core.so.6(Qt_6.11)`. Beim `rpm-ostree install` auf
dem laufenden System scheitert das („cannot install both qt6-qtbase-6.11.1 from
updates and 6.10.2 from @System"), weil Layering keine Basis-Pakete
aktualisiert. Im **Container-Build** hebt `dnf` `qt6-qtbase` als normale
Abhängigkeit an — dort existiert das Problem nicht. Fürs Layering vorher
`rpm-ostree upgrade` + Reboot.

### Rootless gebaut ≠ für `bootc switch` sichtbar

`podman build` (rootless) → `~/.local/share/containers/storage`.
`bootc switch --transport containers-storage` läuft als root → sieht nur
`/var/lib/containers/storage`. Brücke:

```nu
podman save localhost/noctarow:44 | sudo podman load
```

> [!check] Verifiziert
> Binärdaten laufen unverfälscht durch Nushell-Pipes (MD5 identisch vor/nach).
> Das Image liegt danach zweimal auf der Platte, ~6 GB je Kopie → vorher
> `df -h /var`. Beantwortet die offene Frage aus
> [[docs/09-yoga-buildumgebung]]: der Build ist **rootless**, `save | load`
> ist die Brücke.

### Weitere bootc-Befunde

- **„Booted ostree"** ist der erwartete Zustand **vor** dem ersten Switch — das
  System läuft von einer ostree-Ref, nicht von einem Image. Danach „Booted image".
- Gelayertes `nushell` gehört zur Deployment-Kette und **verschwindet beim
  Switch** → muss im Containerfile stehen, sonst keine Login-Shell.
- `sudo rpm-ostree cleanup -r` entfernt das Rollback-Deployment (sonst landet man
  bei einem missglückten Switch in der Exploration-Umgebung).
- `google-chrome`/`rpmfusion-*`-Repos in `/etc/yum.repos.d` gehören dem Paket
  `fedora-workstation-repositories` → **Teil des Basis-Images**, `enabled=0`,
  keine Altlast.

### Terra-Repo

`skip_if_unavailable=False` (Upstream: `True`) — sonst überspringt dnf ein kurz
nicht erreichbares Terra **stillschweigend** und der Build läuft ohne Noctalia
„erfolgreich" durch. **Vendoring ≠ Pinning:** die Datei im Git kontrolliert
Repo-Änderungen, nicht die Paketversion.

## Nushell-Idiome (dieser Session)

| Thema | Befund |
|---|---|
| Umleitung | `2>&1` ist bash. Nushell: `out+err>\|` bzw. kurz `o+e>\|` |
| Regex in `$"…"` | `( )` wird als Subexpression ausgewertet → `(?s)` sucht Kommando `?s`. Klammern escapen: `\(?s\)` |
| `podman images` | liefert **Text**, keine Tabelle → `--format '{{…}}'` oder `from ssv --aligned-columns` |
| `save` ohne `--force` | bricht bei existierender Datei ab („Destination file already exists") — eingebauter Guard für Artefakte |
| `--append` | nicht idempotent → Marker-Guard (`ensure-block`/`remove-block`) |
| `def` | **session-lokal**; nach Shell-Neustart weg → `def` und Aufruf gemeinsam |
| `use` | zur **Parse-Zeit** aufgelöst → Moduldatei muss vorher existieren, sonst wird die **ganze** `config.nu` verworfen |
| `NU_LIB_DIRS` | `$env.NU_LIB_DIRS` aus `env.nu` greift für `use` in `config.nu` — kein `const` nötig |
| `glob` | gibt bei keinem Treffer `[]` zurück (robuster als `ls`, das wirft) |
| Flags in Listen | `[--device /dev/dri]` parst als Strings, Spread mit `...$liste` |
| `mkdir` | legt Elternverzeichnisse automatisch an — kein `-p` |

> [!check] Verifiziert
> Alle Zeilen gegen Nushell 0.114.1 getestet, mehrere davon (Guard, Regex,
> `use`-Parse-Zeit) durch reproduzierten Fehler **und** Fix.

## Test-Methodik

### Grenze von `test-nested` für Env-Fragen

`test-nested` startet `sway -c /etc/sway/config` **direkt** und umgeht
`/usr/bin/start-sway`. Fedora sourct `/etc/sway/environment` aber aus
`start-sway` → **`environment.noctarow` wird im Container nie angewendet**, auch
nach dem Fix. Auf echter Hardware greift es (SDDM ruft `start-sway`). Ergänzt
[[docs/01-erkenntnisse#Was der nested Container nicht testen kann]].

### Erwartetes Rauschen (kein Defekt)

D-Bus/`machine-id`, `No session for pid …`, polkit-Assertion,
`wait-sni-ready`/`assign-cgroups.py`-Tracebacks: brauchen logind + befülltes
`/var`. Im bootc-Image ist `/var` bewusst leer, wird erst beim First Boot
gefüllt.

### Bisect-Disziplin zahlt sich aus

Die `cap_sys_nice`-Diagnose kam aus einem Drei-Wege-Bisect (bash läuft /
`getcap` zeigt Cap / Fehler bleibt ohne `keep-id`), nicht aus einer Vermutung.
Jeder Schritt schloss eine Hypothese aus. Prinzip beibehalten: bei „Operation
not permitted" nicht raten, sondern isolieren.

## Offene Punkte (nur nach dem Switch messbar)

- **swaybar vs. waybar** — `cat 90-bar.conf` settelt es (s. o.)
- **`I3 event socket disconnected` nach ~6 s** — genau die IPC-Verbindung des
  Workspace-Indikators. Container-Artefakt oder echt? Nur auf Hardware messbar.
- **`failed to parse config file`** nach kanshis `Found config *` — Urheber via
  `grep -rn exec /etc/sway /usr/share/sway/config.d` finden
- ~~**`scale 1.5` vs. `scale 2`**~~ — geklärt: `scale 2` war ganzzahlig, aber
  Noctalia/Panels wirkten damit doppelt so groß. `scale 1.5` gesetzt (Repo +
  Live-System), [[docs/05-hidpi-und-monitore]] entsprechend korrigiert.
- **`sddm/`, `tmpfiles/`, `bootc container lint`** — nie gegen einen Build
  verifiziert

## Korrekturen an anderen Notizen

- [ ] [[docs/01-erkenntnisse]] · Umgebungsbefunde: `quickshell` aus Fedora-Repos
  ist für Noctalia v4 **nicht** nutzbar → `noctalia-qs` via Terra (Kollision)
- [ ] [[docs/01-erkenntnisse]] · Kollisionen: `90-bar.conf`-Label
  (swaybar/waybar) erst nach `cat`-Beleg festschreiben — **nicht** blind auf
  waybar ändern
- [ ] [[docs/07-referenz-quellen]] · `quickshell` nicht installieren (kollidiert
  mit `noctalia-qs`)
- [ ] [[docs/09-yoga-buildumgebung]] · `environment` anhängen an
  `/etc/sway/environment`, nicht nach `/usr/share`
- [ ] [[docs/09-yoga-buildumgebung]] · offene Frage „rootless/rootful" ist
  beantwortet: rootless + `save | load`

## Verwandte Notizen

- [[docs/01-erkenntnisse]]
- [[docs/09-yoga-buildumgebung]]
- [[Noctalia im Noctarow-Image – Containerfile und Ablauf]]
