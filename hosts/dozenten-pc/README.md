# Dozenten-PC (Board ASUS P8B75-V)

> [!important] Läuft auf `noctarow-displaylink`, nicht auf dem Basis-Image
> Dieser Rechner hat einen DisplayLink-USB-Adapter (`17e9:4301`,
> USB3→HDMI) fest angeschlossen. Damit dessen dritter Monitor erscheint,
> braucht es evdi + `DisplayLinkManager` — das steckt im **abgeleiteten**
> Image `quay.io/metarow/noctarow-displaylink`, gebaut aus
> `Containerfile.displaylink` (`FROM noctarow:44`), nicht im Basis-Image.
> Architekturentscheidung, Diagnose und alle Stolpersteine:
> [[docs/23-displaylink-evdi-dozenten-pc]].
>
> `noctarow apply-host dozenten-pc` liefert nur die Sway-Configs dieses
> Geräts. Der Umstieg auf das abgeleitete Image ist ein eigener Schritt:
>
>     use scripts/noctarow.nu *
>     noctarow build                       # falls localhost/noctarow:44 fehlt
>     noctarow build-displaylink
>     noctarow to-root --image noctarow-displaylink
>     sudo bootc switch --transport containers-storage localhost/noctarow-displaylink:44
>     sudo systemctl reboot

Desktop-Board, kein Laptop-Panel — Intel Xeon E3-1200v2-iGPU (`i915`,
Ivy-Bridge-Klasse), keine dGPU. Genau der Fall, in dem der
wlroots/evdi-Weg laut Doku zuverlässig läuft (die bekannten Ausfälle
hängen an NVIDIA-/Multi-GPU-Konstellationen).

## Ermittelte Daten

```bash
# Hardware-Identifikation (für den Verzeichnisnamen)
cat /sys/devices/virtual/dmi/id/sys_vendor      # leer/generisch
cat /sys/devices/virtual/dmi/id/product_name    # leer/generisch
cat /sys/devices/virtual/dmi/id/board_name      # P8B75-V
# -> sys_vendor/product_name liefern hier nichts Brauchbares,
#    board_name ist der einzige stabile Identifikator dieses Boards.

# DisplayLink-Adapter erkennen
lsusb | grep -i 17e9
# -> Bus 003 Device 002: ID 17e9:4301 DisplayLink USB3 to HDMI

# Ausgabe. Auf dem Basis-Image nur der Onboard-HDMI-Port; nach dem Umstieg
# auf noctarow-displaylink (2026-09-15 verifiziert) drei aktive Outputs --
# evdi legt card1..card4 an, der DisplayLink-Monitor erscheint als DVI-I-1.
swaymsg -t get_outputs | jq -r '.[] | "\(.name)  \(.make) \(.model)  \(.current_mode.width)x\(.current_mode.height)  scale=\(.scale)"'
# -> DVI-I-1   HP Inc. HP 24fh  1920x1080  scale=1.0   (DisplayLink/evdi)
# -> HDMI-A-1  HP Inc. HP 24fh  1920x1080  scale=1.0   (Onboard)
# -> VGA-1     HP Inc. HP 24fh  1920x1080  scale=1.0   (Onboard)
lsmod | grep evdi                                   # evdi geladen
systemctl is-active displaylink-driver.service      # active

# Eingabegeräte
swaymsg -t get_inputs | jq -r '.[] | "\(.identifier)  type=\(.type)"'
# -> u.a. 16700:8454:DELL_Dell_QuietKey_Keyboard, xkb_active_layout_name = "German (no dead keys)"
```

## Entscheidungen (nach [[docs/22-host-override-neue-hardware]])

- **Kein `70-output.conf`**: 1920×1080 auf `HDMI-A-1`, kein HiDPI. Der
  Image-Default `scale 1` passt unverändert.
- **Kein Touchpad, keine `kanshi-config`**: Desktop-PC mit fester
  Tastatur/Maus, kein bekanntes Dock/Beamer-Wechselszenario. Sollte der
  Dozenten-PC später regelmäßig zwischen Onboard- und DisplayLink-Ausgabe
  umschalten müssen, ist `hosts/yoga920/kanshi-config` die Vorlage für ein
  Mehr-Profil-Setup.
- **`50-keyboard.conf` trotzdem beigelegt**: aktives Layout „German (no
  dead keys)" ist identisch zum Image-Default (`de nodeadkeys`) — Kopie
  als geprüfter Beleg, kein Workaround.

`noctarow apply-host dozenten-pc` deployt die Dateien hier:

- `50-keyboard.conf` → `/etc/sway/config.d/`, verdrängt die gleichnamige
  Default-Datei aus `/usr/share/sway/config.d/` (identisch, siehe oben).
- `noctalia-settings.json` → `~/.config/noctalia/settings.json`. Enthält
  auch persönlichen Zustand (Wallpaper-Pfad, Farbschema, Pinned Apps) —
  nach jeder Änderung in der Noctalia-UI hier manuell nachziehen, sonst
  überschreibt der nächste `apply-host` sie wieder. Vor jedem Commit kurz
  auf `wallhavenApiKey` & Co. prüfen (aktuell leer, unbedenklich).
