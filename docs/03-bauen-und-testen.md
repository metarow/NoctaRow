---
titel: Image bauen und testen
teil_von: "[[README]]"
tags: [podman, bootc, sway, test]
---

# 03 — Bauen und testen

Zwei Stufen, aufsteigend im Aufwand. Build und Test laufen **nativ auf der
Zielmaschine selbst** — x86_64 ist gleichzeitig Build- und Zielarchitektur,
kein Cross-Build, kein Umweg über eine VM. Das gilt für jedes Flottengerät,
nicht nur für den Yoga: gebaut wurde bisher auf dem Yoga und dem Dozenten-PC.

## Stufe 0 — Umgebung prüfen

```nu
use scripts/noctarow.nu *
noctarow doctor
```

Basis-Image gegenprüfen:

```nu
noctarow inspect-base 44
```

## Stufe 1 — Bauen

```nu
noctarow build                      # Tag 44, lokale Architektur (x86_64)
noctarow build --no-cache           # ohne Layer-Cache
```

Das Ergebnis trägt zwei Tags:

- `quay.io/metarow/noctarow:44-amd64` — für den Push
- `localhost/noctarow:44` — für den lokalen Test

> [!warning] `--tag` wechselt nicht die Fedora-Version
> Der Basis-`Containerfile` hat **kein `ARG`**, `FROM …/sway-atomic:44` ist
> fest verdrahtet. `--tag` und `--noctalia-ref` werden zwar als `--build-arg`
> übergeben, aber von niemandem gelesen — podman meldet das beim Build als
> „one or more build args were not consumed". Ein `noctarow build --tag 45`
> erzeugt also ein **44er Image mit falschem Etikett**, keinen
> Rawhide-Vorlauf.
>
> `Containerfile.displaylink` wertet `FEDORA_MAJOR` dagegen korrekt aus. Die
> beiden Dateien verhalten sich hier unterschiedlich. Zu entscheiden: `ARG`
> im Basis-`Containerfile` nachrüsten oder die wirkungslosen Flags aus
> `scripts/noctarow.nu` entfernen. Steht als offener Punkt im Root-`README.md`.

### Abgeleitetes DisplayLink-Image

Nur für den Dozenten-PC, setzt den Basis-Build voraus:

```nu
noctarow build-displaylink          # -> localhost/noctarow-displaylink:44
```

Was dabei zu prüfen ist, steht in
[[docs/23-displaylink-evdi-dozenten-pc#Verifikation vor dem Switch (ohne Reboot)]].

## Stufe 2 — Nested Sway (der eigentliche Arbeitszyklus)

```nu
noctarow test-nested
```

Ein Sway-Fenster in deiner laufenden Sway-Session, mit echter GPU —
hardwarebeschleunigt, kein Software-Rendering. Iterationszyklus: Sekunden.

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
>
> Nichts davon ist ein Problem deines Images. Auf echter Hardware läuft der
> nested Test hardwarebeschleunigt gegen die reale GPU — ruckelnde Animationen
> sind hier **kein** erwartetes Rauschen mehr, sondern ein echter Befund.

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

## Was ein nested Test nicht abdeckt

Für das, was ein Container nicht abbilden kann — ostree-Deployment,
`systemd-tmpfiles` ins `$HOME`, SDDM, das `/etc`-3-Wege-Merge über zwei
Image-Generationen — bleibt nur der echte `bootc switch` auf dem Gerät selbst,
siehe [[docs/06-lenovo-yoga-deployment]]. Eine separate VM-Teststufe entfällt,
weil jede Maschine gleichzeitig Build- **und** Zielmaschine ist: ein
missglückter Switch ist ein `bootc rollback` entfernt, nicht ein VM-Neuaufbau.

Der Merge-Test (Image mit geänderter `/usr/share/sway/config.d/50-keyboard.conf`
neu bauen, switchen, prüfen ob eine lokal angelegte
`/etc/sway/config.d/50-keyboard.conf` überlebt) läuft entsprechend direkt auf
dem Gerät — mit `bootc rollback` als Sicherheitsnetz, nicht in einer VM.

## Warum Sway nested aussagekräftig ist

Der wlroots-Wayland-Backend legt ein virtuelles Keyboard an, auf das Sway
seine eigene XKB-Konfiguration anwendet. Die Config-Kette wird also echt
getestet — und läuft auf der Zielhardware hardwarebeschleunigt gegen die reale
GPU, ohne den Software-Rendering-Kompromiss (`WLR_RENDERER=pixman`) früherer
WSL-Testläufe.
