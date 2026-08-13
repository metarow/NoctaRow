---
titel: Image bauen und testen
teil_von: "[[README]]"
tags: [podman, bootc, sway, test, hyperv]
---

# 03 — Bauen und testen

Drei Stufen, aufsteigend im Aufwand. Die meiste Arbeit passiert in Stufe 1.

## Stufe 0 — Umgebung prüfen

```nu
use scripts/noctarow.nu *
noctarow doctor
```

Erwartete Ausgabe: alles ✓ außer `/dev/dri`, das in Fedora-WSL fehlt und
fehlen darf.

Basis-Image gegenprüfen:

```nu
noctarow base-arches 44
noctarow inspect-base 44
```

## Stufe 1 — Bauen

```nu
noctarow build                      # Tag 44, lokale Architektur
noctarow build --tag 45 --no-cache  # Rawhide-Vorlauf
noctarow build --noctalia-ref v5.2.0
```

Das Ergebnis trägt zwei Tags:

- `quay.io/metarow/noctarow:44-arm64` — für den Push
- `localhost/noctarow:44` — für den lokalen Test

> [!note] Warum arch-Suffix
> Auf dem XPS kannst du nur nativ `arm64` bauen, auf dem CachyOS-Desktop nur
> nativ `amd64`. Emulation über `qemu-user`/binfmt funktioniert zwar, dauert
> aber Größenordnungen länger. Beide Seiten pushen ihr Arch-Image, danach wird
> die Manifest-List gebaut. Siehe [[docs/04-quay-veroeffentlichung]].

## Stufe 2 — Nested Sway (der eigentliche Arbeitszyklus)

```nu
noctarow test-nested
```

Es öffnet sich ein Fenster auf dem Windows-Desktop mit Sway und Noctalia
darin. Iterationszyklus: Sekunden.

Innerhalb der Session, oder von außen mit gesetztem `SWAYSOCK`:

```nu
noctarow keyboard-check
```

```
╭───┬────────────────────┬────────────────────────╮
│ # │     identifier     │ xkb_active_layout_name │
├───┼────────────────────┼────────────────────────┤
│ 0 │ 1:1:...            │ German (no dead keys)  │
╰───┴────────────────────┴────────────────────────╯
```

Steht dort `German (no dead keys)`, trägt die Drop-in-Kette.

### Was hier scheitern *darf*

> [!warning] Erwartete Fehlermeldungen
> - `sway-session.target` nicht gefunden → `10-systemd-session.conf` läuft ins
>   Leere, weil im Container keine systemd-User-Session existiert
> - `95-xdg-desktop-autostart.conf` bleibt wirkungslos
> - Ruckelnde Animationen → `WLR_RENDERER=pixman`, Software-Rendering
>
> Nichts davon ist ein Problem deines Images.

### Was hier *nicht* scheitern darf

- Sway startet und zeigt ein Fenster
- Noctalias Panel erscheint
- `keyboard-check` meldet das deutsche Layout
- **Noctalia schreibt nicht nach `/usr`** — dort ist auf bootc read-only

Zum letzten Punkt: falls Quickshell beim Start in sein Installationsverzeichnis
schreiben will, siehst du das hier sofort. Dann muss der Pfad nach
`~/.config/quickshell/` gespiegelt werden, statt direkt aus `/usr/share`
geladen zu werden.

Für Debugging eine Shell statt Sway:

```nu
noctarow test-nested --shell
```

## Stufe 3 — Hyper-V

Nur für das, was ein Container nicht abbilden kann: ostree-Deployment,
`systemd-tmpfiles` ins `$HOME`, SDDM, das `/etc`-3-Wege-Merge über zwei
Image-Generationen.

Das sind vier, fünf Bootvorgänge über das ganze Projekt — nicht dein
Arbeitszyklus.

### Disk-Image erzeugen

In WSL, **auf ext4** — nicht unter `/mnt/c`. Siehe [[docs/08-verteilung]].

```nu
noctarow disk --tag 44
```

Das erzeugt `output/image/disk.raw` per `bootc-image-builder` und konvertiert
nach `output/noctarow-44.vhdx`. `--type raw`, nicht `qcow2` — Hyper-V will
VHDX.

> [!important] Voraussetzungen
> Loop-Devices im privilegierten Container und `/` als `shared` gemountet.
> Beides setzt `/etc/wsl.conf`, siehe
> [[docs/02-umgebung-wsl#wsl.conf — systemd und shared mounts]].
> `noctarow disk` bricht ab, wenn das Dateisystem nicht `ext4` ist.

Von Windows aus in einem Schritt, inklusive Kopie nach NTFS:

```nu
nw sync-vhdx --tag 44
```

### VM anlegen

Auf Windows, Nushell, **als Administrator**:

```nu
use scripts/noctarow-win.nu *
nw vm-create --tag 44
nw vm-start
```

Die VHDX wird unter `C:\Hyper-V\noctarow\` erwartet — dorthin hat sie
`nw sync-vhdx` gelegt. Das Skript setzt Generation 2 (UEFI, Pflicht auf ARM),
deaktiviert Secure Boot und prüft vorher, ob es in einer Administrator-Shell
läuft.

### Grafik in Hyper-V

Hyper-V gibt Linux-Gästen nur den `hyperv_drm`-Framebuffer. Kein
GPU-Backend, kein Hardware-Cursor. Sway braucht deshalb auch dort:

```
WLR_RENDERER=pixman
```

Auflösung per Kernel-Argument festnageln, sonst bleibt es bei 1024×768:

```
video=hyperv_fb:1920x1080
```

Für ein bootc-Image gehört das in die Kernel-Args des Deployments, nicht ins
Containerfile:

```bash
sudo bootc kargs --append video=hyperv_fb:1920x1080
```

> [!caution] Erwartungshaltung
> Das ruckelt, Noctalias Animationen sehen furchtbar aus. Egal — hier testest
> du nicht die Optik, sondern ob das Image sauber hochkommt.

### Was in der VM geprüft wird

```nu
systemctl --user status sway-session.target
ls ~/.config/noctalia ~/.config/sway/config.d
cat /etc/vconsole.conf                 # tmpfiles muss ihn angelegt haben
localectl status
bootc status
```

Und dann der Merge-Test: Image mit einer geänderten
`/usr/share/sway/config.d/50-keyboard.conf` neu bauen, pushen, in der VM
`bootc upgrade`, rebooten — und prüfen, ob ein lokal angelegtes
`/etc/sway/config.d/50-keyboard.conf` überlebt hat. Das ist die Frage, die
für die Flotte zählt.

## Warum Sway nested, nicht als VM

Der wlroots-Wayland-Backend legt ein virtuelles Keyboard an, auf das Sway
seine eigene XKB-Konfiguration anwendet. Die Config-Kette wird also echt
getestet.

> [!note] Eine Einschränkung
> WSLg sitzt als eigener Compositor davor und mappt Windows-Tastendrücke
> bereits auf Keycodes. Bei einem simplen `de`-Layout stört das nicht; bei
> exotischen `xkb_options` können sich die beiden Ebenen in die Quere kommen.
> Für „greift mein Drop-in überhaupt" ist der Test aussagekräftig.
