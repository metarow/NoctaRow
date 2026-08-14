---
titel: Image bauen und testen
teil_von: "[[README]]"
tags: [podman, bootc, sway, test]
---

# 03 — Bauen und testen

Zwei Stufen, aufsteigend im Aufwand. Build und Test laufen **nativ auf dem
Yoga** — x86_64 ist gleichzeitig Build- und Zielarchitektur, kein
Cross-Build, kein Umweg über eine VM.

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
noctarow build --tag 45 --no-cache  # Rawhide-Vorlauf
noctarow build --noctalia-ref v5.2.0
```

Das Ergebnis trägt zwei Tags:

- `quay.io/metarow/noctarow:44-amd64` — für den Push
- `localhost/noctarow:44` — für den lokalen Test

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
> Nichts davon ist ein Problem deines Images. Auf dem Yoga läuft der nested
> Test hardwarebeschleunigt gegen die reale GPU — ruckelnde Animationen sind
> hier **kein** erwartetes Rauschen mehr, sondern ein echter Befund.

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
Image-Generationen — bleibt nur der echte `bootc switch` auf dem Yoga selbst,
siehe [[docs/06-lenovo-yoga-deployment]]. Eine separate VM-Teststufe entfällt,
weil der Yoga gleichzeitig Build- **und** Zielmaschine ist: ein missglückter
Switch ist ein `bootc rollback` entfernt, nicht ein VM-Neuaufbau.

Der Merge-Test (Image mit geänderter `/usr/share/sway/config.d/50-keyboard.conf`
neu bauen, pushen/switchen, prüfen ob eine lokal angelegte
`/etc/sway/config.d/50-keyboard.conf` überlebt) läuft entsprechend direkt auf
dem Yoga — mit `bootc rollback` als Sicherheitsnetz, nicht in einer VM.

## Warum Sway nested aussagekräftig ist

Der wlroots-Wayland-Backend legt ein virtuelles Keyboard an, auf das Sway
seine eigene XKB-Konfiguration anwendet. Die Config-Kette wird also echt
getestet — und läuft auf dem Yoga hardwarebeschleunigt gegen die reale GPU,
ohne den Software-Rendering-Kompromiss (`WLR_RENDERER=pixman`) früherer
WSL-Testläufe.
