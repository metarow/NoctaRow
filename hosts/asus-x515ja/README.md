# ASUS VivoBook X515JA (R565JA)

> [!info] Live getestet, 25.08.2026
> Gefixtes Image (`noctalia-legacy`, `/usr`-Spiegel, Verzeichnis-Modus)
> per `bootc upgrade` + Reboot deployt und verifiziert: Bar/Dock/Launcher
> sichtbar und funktional, Journal sauber. Details und ein Stolperstein
> beim Rollout (`switch` vs. `upgrade`):
> [[docs/24-noctarow-noctalia-handover]], [[docs/06-lenovo-yoga-deployment#Umschalten]].

15,6" FHD-Panel (1920x1080), kein HiDPI im technischen Sinn -- aber bei
`scale 1` (Image-Default) auf dem kleinen 15,6"-Panel gefühlt zu klein.
`70-output.conf` setzt `scale 1.3` auf `eDP-1` (gezielt, nicht `output *`,
damit ein externer Monitor nicht mitskaliert). Am Gerät nachjustiert,
2026-08-25. Kein Dock/Beamer-Szenario bekannt, deshalb noch keine
`kanshi-config` -- Vorlage für ein Mehr-Profil-Setup:
[[hosts/yoga920/kanshi-config]].

Touchpad ist ein ELAN1200 (`04F3:309F`), Werte identisch zum Image-Default
(`tap`, `natural_scroll`, `dwt` aktiv). `50-keyboard.conf` liegt trotzdem
bei, weil sie auf dem Gerät verifiziert wurde -- siehe
[[hosts/yoga920/50-keyboard.conf]] für dasselbe Muster.

Am Gerät hängt zusätzlich ein Telink-Funkempfänger (Maus/Tastatur-Kombo,
`9354:33639`). Das ist ein optionales USB-Peripheriegerät, kein fester
Bestandteil der Hardware -- bewusst nicht in die Host-Config aufgenommen.

## Ermittelte Daten

```bash
# Hardware-Identifikation (für den Verzeichnisnamen)
cat /sys/devices/virtual/dmi/id/sys_vendor      # ASUSTeK COMPUTER INC.
cat /sys/devices/virtual/dmi/id/product_name    # VivoBook_ASUSLaptop X515JA_R565JA
cat /sys/devices/virtual/dmi/id/board_name      # X515JA

# Ausgabe
swaymsg -t get_outputs | jq -r '.[] | "\(.name)  \(.make) \(.model)  \(.current_mode.width)x\(.current_mode.height)@\(.current_mode.refresh/1000)Hz  scale=\(.scale)"'
# -> eDP-1  Chimei Innolux Corporation 0x15F5  1920x1080@60.008Hz  scale=1.0

# Eingabegeräte
swaymsg -t get_inputs | jq -r '.[] | "\(.identifier)  type=\(.type)"'
swaymsg -t get_inputs | jq '.[] | select(.type=="touchpad")'
```

Vollständiger Ablauf inkl. Entscheidungslogik (Override nötig oder nicht):
[[docs/22-host-override-neue-hardware]].

`noctarow apply-host asus-x515ja` deployt die Dateien hier:

- `*.conf` → `/etc/sway/config.d/`, verdrängt die gleichnamigen Defaults
  aus `/usr/share/sway/config.d/`.
- `noctalia-settings.json` → `~/.config/noctalia/settings.json`. Enthält
  auch persönlichen Zustand (Wallpaper-Pfad, Farbschema, Pinned Apps) --
  nach jeder Änderung in der Noctalia-UI hier manuell nachziehen, sonst
  überschreibt der nächste `apply-host` sie wieder.
