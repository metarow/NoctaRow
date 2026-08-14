# Lenovo Yoga 920-13IKB

13,9" Panel. Je nach Variante FHD (1920x1080) oder **4K UHD (3840x2160)**.
Bei 4K laeuft eDP-1 mit `scale 1.5` (2560x1440 logisch) — ganzzahliges
`scale 2` war zu grob, Panels/Noctalia wirkten doppelt so gross. Details:
[[docs/05-hidpi-und-monitore]].

Ausgabename ermitteln:

    swaymsg -t get_outputs | jq -r '.[] | "\(.name)  \(.make) \(.model)  \(.current_mode.width)x\(.current_mode.height)"'

`noctarow apply-host yoga920` deployt die Dateien hier:

- `*.conf` → `/etc/sway/config.d/`, verdraengt die gleichnamigen Defaults
  aus `/usr/share/sway/config.d/`.
- `kanshi-config` → `~/.config/kanshi/config`.
- `noctalia-settings.json` → `~/.config/noctalia/settings.json`. Enthaelt
  auch persoenlichen Zustand (Wallpaper-Pfad, Farbschema, Pinned Apps) —
  nach jeder Aenderung in der Noctalia-UI hier manuell nachziehen, sonst
  ueberschreibt der naechste `apply-host` sie wieder.
