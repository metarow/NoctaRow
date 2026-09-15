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
was überhaupt abweicht — durchgespielt an
[[hosts/yoga920/README|Yoga 920]], [[hosts/asus-x515ja/README|ASUS X515JA]]
und [[hosts/dozenten-pc/README|Dozenten-PC]].

## Ablauf

### 1. Gerät identifizieren (Verzeichnisname)

```bash
cat /sys/devices/virtual/dmi/id/sys_vendor
cat /sys/devices/virtual/dmi/id/product_name
cat /sys/devices/virtual/dmi/id/board_name
```

Konvention: kurz, aus Hersteller + Modell/Board, z. B. `yoga920`,
`asus-x515ja`. Kein Anspruch auf eine feste Namensschablone — der Name ist
nur der Schlüssel für `noctarow apply-host`. Liefern `sys_vendor` und
`product_name` nichts Brauchbares, wie bei Eigenbau-Desktops, ist
`board_name` der stabilste Identifikator (Beispiel `dozenten-pc`, Board
`P8B75-V`).

### 1b. Reicht das Basis-Image, oder braucht das Gerät eine eigene Variante?

Diese Frage vor allem anderen klären, denn sie entscheidet über den ganzen
Rollout-Weg. Ein Host-Override kann nur `/etc` und `~/.config` verändern. Was
**Pakete, Kernelmodule oder Startparameter** braucht, geht damit nicht.

```bash
lsusb        # Adapter mit eigenem Treiberbedarf, z. B. DisplayLink (17e9)
lspci | grep -iE 'vga|3d|nvidia'   # dGPU? -> eigene Treiberschicht nötig
```

| Befund | Weg |
|---|---|
| Nur Panel/Tastatur/Skalierung weichen ab | Host-Override, dieser Ablauf ab Schritt 2 |
| Zusätzliche Kernelmodule oder proprietäre Daemons nötig | **abgeleitetes Image** `FROM noctarow:44`, zusätzlich zum Host-Override |

Bisher genau ein Fall der zweiten Sorte: Der Dozenten-PC braucht `evdi` plus
`DisplayLinkManager` und `sway --unsupported-gpu`. Das liegt in
`Containerfile.displaylink` und wird mit `noctarow build-displaylink` gebaut.
Warum das nicht ins Basis-Image gehört, steht in
[[docs/23-displaylink-evdi-dozenten-pc#Architekturentscheidung: evdi gehört NICHT ins Basis-Image]].

Beides schließt sich nicht aus: Ein Gerät mit eigener Image-Variante bekommt
**trotzdem** ein `hosts/<name>/` für Ausgabe, Tastatur und Noctalia-Settings.
Die Variante liefert die Systemschicht, der Override die Sitzungsschicht.

### 2. Ausgabe prüfen — braucht es ein `70-output.conf`?

```bash
swaymsg -t get_outputs | jq -r '.[] | "\(.name)  \(.make) \(.model)  \(.current_mode.width)x\(.current_mode.height)@\(.current_mode.refresh/1000)Hz  scale=\(.scale)"'
```

Der Image-Default in `/usr/share/sway/config.d/70-output.conf` setzt
`scale 1` auf allen Ausgängen — bewusst konservativ, siehe Kommentar dort.
Passt das technisch (Full-HD/1080p-Panel, kein HiDPI): erstmal **kein**
`70-output.conf` anlegen, im Host-`README.md` kurz begründen, warum keins
nötig ist.

Zwei Gründe für ein eigenes `70-output.conf` trotzdem:

- **HiDPI-Panel**, sichtbar zu kleine oder unscharfe UI bei `scale 1`:
  fraktionale Skalierung nach dem Muster von `hosts/yoga920/70-output.conf`.
  Faustregel und Hintergrund: [[docs/05-hidpi-und-monitore]].
- **Kleines Panel, technisch aber kein HiDPI**: `scale 1` ist zwar korrekt
  scharf, aber auf z. B. 13–15" gefühlt zu klein. Beispiel
  `hosts/asus-x515ja/70-output.conf` (15,6" FHD, `scale 1.3` gezielt auf
  den Panel-Output, nicht `output *`, damit ein extern angeschlossener
  Monitor nicht mitskaliert). Das ist Geschmackssache am Gerät, nicht per
  Formel herleitbar — vor Ort ausprobieren.

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
(nicht nur das Ergebnis — wer als Nächstes ein Gerät anbindet, soll die
Befehle kopieren können). Läuft das Gerät auf einer eigenen Image-Variante
(Schritt 1b), gehört das **als Erstes** ins Host-README, samt der
Build- und Switch-Befehle. Muster:
[[hosts/dozenten-pc/README|hosts/dozenten-pc]].

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
Image-Tag und Host-Override-Pfad. Bei einer eigenen Image-Variante gehört
deren Tag in die Spalte, nicht der des Basis-Images (Beispiel:
`44-displaylink` beim Dozenten-PC).
