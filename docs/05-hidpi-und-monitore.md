---
titel: HiDPI, Skalierung und Monitore
teil_von: "[[README]]"
tags: [hidpi, skalierung, sway, kanshi, sddm, beamer, xwayland]
---

# 05 — HiDPI, Skalierung, Monitore

## Der Grundsatz: ganzzahlig, wenn möglich

Sway kann fraktionale Skalierung (`scale 1.5`). Der Preis: **XWayland-Fenster
werden unscharf.** Xwayland kennt keine fraktionale Skalierung, Sway rendert
die Anwendung auf `1` und skaliert das Ergebnis hoch.

Bei Wayland-nativen Anwendungen ist fraktional inzwischen sauber (via
`wp_fractional_scale_v1`). In einer Schulungsumgebung mit LibreOffice, Zoom,
Legacy-Java-Tools ist XWayland aber garantiert im Spiel.

| Panel | Auflösung | Empfehlung | Logisch |
|---|---|---|---|
| Yoga 920, 4K | 3840×2160 @ 13,9" | `scale 2` | 1920×1080 |
| Yoga 920, FHD | 1920×1080 @ 13,9" | `scale 1` | 1920×1080 |
| Beamer | 1920×1080 | `scale 1` | 1920×1080 |
| Externer 27" WQHD | 2560×1440 | `scale 1` | 2560×1440 |

> [!tip] Das Yoga 920 ist ein Glücksfall
> 3840×2160 bei `scale 2` ergibt exakt 1920×1080 logisch. Ganzzahlig, also
> keine XWayland-Unschärfe, und die logische Größe entspricht dem, was ein
> Beamer ohnehin liefert. Beides nebeneinander funktioniert ohne Kompromiss.

Panel-Variante feststellen:

```nu
swaymsg -t get_outputs
| from json
| select name make model current_mode.width current_mode.height scale
```

## Wo die Skalierung konfiguriert wird

Nach dem Schichtenmodell aus [[docs/01-erkenntnisse]]:

- **Image-Default** (`/usr/share/sway/config.d/70-output.conf`): bewusst
  konservativ, `output * scale 1`. Ein unbekanntes Gerät startet damit
  vielleicht mit winziger Schrift, aber es startet.
- **Maschinenspezifisch** (`/etc/sway/config.d/70-output.conf`): verdrängt den
  Default. Kommt aus `hosts/<maschine>/`.

Deployment auf dem Zielrechner:

```nu
use scripts/noctarow.nu *
noctarow apply-host yoga920
swaymsg reload
```

## Umgebungsvariablen — weniger ist mehr

> [!danger] Nicht setzen
> `GDK_SCALE`, `GDK_DPI_SCALE`, `QT_SCALE_FACTOR`,
> `QT_AUTO_SCREEN_SCALE_FACTOR`
>
> Unter Wayland handeln GTK4 und Qt6 die Skalierung direkt mit dem Compositor
> aus. Zusätzliche Faktoren multiplizieren sich und führen zu doppelt
> skalierten Fenstern. Das ist der häufigste HiDPI-Fehler und er kommt fast
> immer aus einer kopierten X11-Anleitung.

Was sinnvoll ist, gehört ins Image nach `/usr/share/sway/environment` bzw.
`/etc/sway/environment`:

```sh
# Qt: Wayland-Backend erzwingen, sonst fällt es auf XWayland zurück
QT_QPA_PLATFORM=wayland;xcb

# Cursor: Sway skaliert die Größe automatisch mit dem Output-Scale
XCURSOR_SIZE=24
XCURSOR_THEME=Adwaita

# Firefox/Chromium: Wayland-nativ
MOZ_ENABLE_WAYLAND=1
```

Bei `scale 2` wird aus `XCURSOR_SIZE=24` automatisch ein 48-Pixel-Cursor.
`XCURSOR_SIZE=48` zu setzen ist der zweithäufigste Fehler.

## Noctalia

Quickshell ist Qt6-basiert und folgt dem Compositor-Scale. Es sollte also
nichts zu tun sein.

> [!warning] Zu prüfen
> Noctalia v5 bringt eine eigene Skalierungseinstellung in seiner
> Konfiguration mit. Wenn Panel und Widgets bei `scale 2` doppelt so groß
> aussehen wie gewollt, ist das der Grund — nicht Sway. Der Wert gehört dann
> auf `1`, weil Sway die Skalierung bereits erledigt.

## Mehrere Monitore: kanshi

Statisch in der Sway-Config zu skalieren funktioniert nur, solange sich nichts
ändert. Im Schulungsbetrieb hängt der Beamer mal dran, mal nicht.
**`kanshi`** löst das deklarativ und ist im Image enthalten.

`~/.config/kanshi/config` (Vorlage in `hosts/yoga920/kanshi-config`):

```
profile mobil {
    output eDP-1 enable mode 3840x2160 position 0,0 scale 2
}

profile beamer {
    output eDP-1  enable mode 3840x2160 position 0,0    scale 2
    output HDMI-A-1 enable mode 1920x1080 position 1920,0 scale 1
}

profile dock {
    output eDP-1 disable
    output DP-1  enable mode 2560x1440 position 0,0 scale 1
}
```

kanshi wählt beim Anstecken automatisch das passende Profil anhand der
angeschlossenen Ausgänge.

> [!caution] Spiegeln bei unterschiedlicher Skalierung
> Ein gespiegelter Beamer (`output HDMI-A-1 position 0,0` bei gleichzeitig
> `scale 2` auf dem Panel) zwingt Sway zu einer Software-Kopie des
> Framebuffers. Das kostet spürbar Leistung.
>
> Für Präsentationen besser: **nebeneinander**, und das zu zeigende Fenster auf
> den Beamer schieben. Oder für die Dauer der Präsentation `scale 1` auf dem
> Panel.

## Der Login-Screen

SDDM läuft **vor** der Sway-Session. Weder das Sway-Drop-in noch
`~/.config/kanshi/config` wirken dort.

Das Image liefert `/usr/lib/sddm/sddm.conf.d/10-noctarow.conf`:

```ini
[Wayland]
EnableHiDPI=true

[X11]
EnableHiDPI=true
```

> [!note] EnableHiDPI ist grob
> Es verdoppelt bei hoher DPI, es skaliert nicht fein. Für ein 4K-13,9"-Panel
> ist das genau richtig; für ein 1440p-27"-Display ist es zu viel. Falls du
> gemischte Hardware hast, gehört die Datei nach `/etc/sddm.conf.d/` und wird
> pro Maschine ausgeliefert.

### Tastatur im Login-Screen

Kommt nicht aus Sway, sondern aus `/etc/vconsole.conf`. Das Image liefert eine
Vorlage, die `systemd-tmpfiles` beim ersten Boot nach `/etc` kopiert **falls
dort noch keine liegt** (Typ `C` überschreibt nie):

```
KEYMAP=de-nodeadkeys
FONT=eurlatgr
```

Nachträglich ändern:

```nu
sudo localectl set-keymap de-nodeadkeys
sudo localectl set-x11-keymap de "" nodeadkeys
```

`set-x11-keymap` schreibt `/etc/X11/xorg.conf.d/00-keyboard.conf`. Sway liest
das nicht — aber SDDMs X11-Greeter schon, und es ist die Quelle, aus der die
`locale1`-Brücke schöpfen würde, falls du sie später doch einsetzt.

> [!important] Drei Orte, eine Belegung
> | Ort | Quelle |
> |---|---|
> | TTY | `/etc/vconsole.conf` |
> | SDDM-Greeter | `localectl` / `00-keyboard.conf` |
> | Sway-Session | `/usr/share/sway/config.d/50-keyboard.conf` |
>
> Alle drei müssen übereinstimmen. Sie tun es nicht von allein.
