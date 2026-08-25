---
titel: Host-Override für neue Hardware anlegen
teil_von: "[[README]]"
tags: [bootc, sway, hosts, hardware, deployment]
---

# 22 — Host-Override für neue Hardware anlegen

Das Image ist für alle Geräte identisch (siehe
[[docs/06-lenovo-yoga-deployment#Maschinenspezifische Konfiguration]]).
Abweichungen kommen als `hosts/<name>/` ins Repo und werden per
`noctarow apply-host <name>` auf dem jeweiligen Gerät nachgezogen. Dieses
Dokument ist der wiederholbare Ablauf, um für ein neues Gerät zu ermitteln,
was überhaupt abweicht — am [[hosts/asus-x515ja/README|ASUS X515JA]] als
zweitem Beispiel neben [[hosts/yoga920/README|Yoga 920]] durchgespielt.

## Ablauf

### 1. Gerät identifizieren (Verzeichnisname)

```bash
cat /sys/devices/virtual/dmi/id/sys_vendor
cat /sys/devices/virtual/dmi/id/product_name
cat /sys/devices/virtual/dmi/id/board_name
```

Konvention: kurz, aus Hersteller + Modell/Board, z. B. `yoga920`,
`asus-x515ja`. Kein Anspruch auf eine feste Namensschablone — der Name ist
nur der Schlüssel für `noctarow apply-host`.

### 2. Ausgabe prüfen — braucht es ein `70-output.conf`?

```bash
swaymsg -t get_outputs | jq -r '.[] | "\(.name)  \(.make) \(.model)  \(.current_mode.width)x\(.current_mode.height)@\(.current_mode.refresh/1000)Hz  scale=\(.scale)"'
```

Der Image-Default in `/usr/share/sway/config.d/70-output.conf` setzt
`scale 1` auf allen Ausgängen — bewusst konservativ, siehe Kommentar dort.
Passt das (Full-HD/1080p-Panel, kein HiDPI): **kein** `70-output.conf`
anlegen, im Host-`README.md` kurz begründen, warum keins nötig ist
(Beispiel: `hosts/asus-x515ja/README.md`).

Passt es nicht (HiDPI-Panel, sichtbar zu kleine oder unscharfe UI): eigenes
`70-output.conf` nach dem Muster von `hosts/yoga920/70-output.conf`.
Faustregel und Hintergrund zur fraktionalen Skalierung:
[[docs/05-hidpi-und-monitore]].

### 3. Eingabegeräte prüfen — braucht es ein `50-keyboard.conf`?

```bash
swaymsg -t get_inputs | jq -r '.[] | "\(.identifier)  type=\(.type)"'
swaymsg -t get_inputs | jq '.[] | select(.type=="touchpad")'
```

Layout/Variante/Touchpad-Verhalten mit dem Image-Default in
`/usr/share/sway/config.d/50-keyboard.conf` vergleichen. Weicht nichts ab,
trotzdem eine Kopie ins Host-Verzeichnis legen und im README als
"identisch zum Default, hier als Beleg" kennzeichnen (siehe beide
bestehenden Hosts) — das dokumentiert, dass es geprüft wurde, statt einer
stillen Annahme.

Externe/optionale Peripherie (Funkempfänger, angesteckte Tastaturen) taucht
in `get_inputs` mit auf, gehört aber **nicht** in die Host-Config — die ist
für die feste Hardware des Geräts, nicht für was gerade eingesteckt ist.

### 4. Mehrfach-Ausgaben — braucht es eine `kanshi-config`?

Nur relevant, wenn das Gerät regelmäßig an Dock/Beamer hängt. Ohne
bekanntes Szenario keine Datei anlegen; Vorlage für später:
`hosts/yoga920/kanshi-config` (Profile `mobil`/`beamer`/`dock`).

### 5. Noctalia-Settings sichern

```bash
cp ~/.config/noctalia/settings.json hosts/<name>/noctalia-settings.json
```

Enthält auch persönlichen Zustand (Wallpaper-Pfad, Farbschema, Pinned
Apps) — nach jeder Änderung in der Noctalia-UI hier manuell nachziehen,
sonst überschreibt der nächste `apply-host` sie wieder. Vor dem Commit kurz
mit `jq` durchsehen (`wallhavenApiKey` & Co.), ob wirklich nichts
Sensibles drinsteckt — bei Standard-Feldern (Layout, Wallpaper-Pfad,
Farbschema) unbedenklich.

### 6. README schreiben, anwenden, verifizieren

README im Host-Verzeichnis: Panel/Touchpad-Modell, welche Dateien warum
(nicht) angelegt wurden, die exakten Befehle aus Schritt 1–4 als Beleg
(nicht nur das Ergebnis — der nächste, der ein drittes Gerät anbindet, soll
die Befehle kopieren können).

```bash
noctarow apply-host <name>
noctarow keyboard-check
noctarow output-check
pgrep -a qs
```

Prüfliste für die erste Inbetriebnahme insgesamt:
[[docs/06-lenovo-yoga-deployment#Erstinbetriebnahme — Prüfliste]].

### 7. Flotten-Tabelle aktualisieren

Neue Zeile in
[[docs/06-lenovo-yoga-deployment#Für die Flotte]] mit Architektur,
Image-Tag und Host-Override-Pfad.
