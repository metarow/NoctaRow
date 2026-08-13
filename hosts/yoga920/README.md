# Lenovo Yoga 920-13IKB

13,9" Panel. Je nach Variante FHD (1920x1080) oder **4K UHD (3840x2160)**.
Bei 4K ergibt Skalierung 2 exakt 1920x1080 logisch — ganzzahlig, also keine
XWayland-Unschaerfe.

Ausgabename ermitteln:

    swaymsg -t get_outputs | jq -r '.[] | "\(.name)  \(.make) \(.model)  \(.current_mode.width)x\(.current_mode.height)"'

Dateien hier werden nach /etc/sway/config.d/ deployt und verdraengen die
gleichnamigen Defaults aus /usr/share/sway/config.d/.
