---
titel: Deployment auf dem Lenovo Yoga 920
teil_von: "[[README]]"
tags: [bootc, deployment, yoga920, rebase, rollback]
zielgeraet: Lenovo Yoga 920-13IKB (x86_64)
---

# 06 — Deployment auf dem Lenovo Yoga 920

Das Yoga ist die erste Plattform für das Basis-Image: x86_64, native Build-
und Zielhardware in einem, kein Cross-Build, keine VM dazwischen.

## Voraussetzung

Auf dem Yoga muss ein **bootc-fähiges System** laufen. Zwei Wege:

**A — schon Fedora Sway Atomic installiert:** direkt umschalten.

**B — Neuinstallation:** ISO von Fedora Sway Atomic installieren, dann
umschalten. Der Umweg über Sway Atomic statt direkt Noctarow ist bewusst — du
willst wissen, dass die Hardware mit dem Basis-Image läuft, bevor deine
Ergänzungen im Spiel sind.

## Umschalten

```nu
sudo bootc switch quay.io/metarow/noctarow:44
systemctl reboot
```

Für die Flotte stattdessen den gepinnten Stand:

```nu
sudo bootc switch quay.io/metarow/noctarow:stable
```

Nach dem Reboot:

```nu
bootc status
```

Zeigt das gebootete Image, das gestagete Image und den Rollback-Stand.

> [!warning] Lokaler Rebuild auf der Zielmaschine: `switch` ist ein No-Op, wenn die Referenz schon getrackt wird
> Wenn Build- und Zielmaschine dieselbe ist (`noctarow build` → `noctarow
> to-root` → `bootc switch --transport containers-storage
> localhost/noctarow:44`), vergleicht `switch` nur den Referenz-String
> (Transport + Name + Tag), nicht den Bildinhalt. Läuft die Maschine
> bereits auf genau dieser Referenz -- etwa weil schon einmal umgeschaltet
> wurde -- meldet `switch` **„Image specification is unchanged."** und tut
> nichts, obwohl `to-root` frischen Inhalt nach root's Storage kopiert hat.
> Für „gleiche Referenz, neuer Inhalt" `sudo bootc upgrade` statt `switch`
> verwenden. `bootc status` danach zeigt eine neue `UpdateDigest`/
> `Version`, wenn es gegriffen hat. Am ASUS X515JA reproduziert (siehe
> [[docs/noctarow-noctalia-handover]]).

## Rollback

Das ist das Argument für bootc, und es sollte einmal bewusst geübt werden:

```nu
sudo bootc rollback
systemctl reboot
```

Bootet den vorherigen Stand. Nichts wurde überschrieben; die alte Deployment
liegt noch da.

> [!tip] Vor dem ersten Kurs
> Einmal absichtlich ein kaputtes Image ausrollen und zurückrollen. Wenn du
> das im Ernstfall zum ersten Mal machst, machst du es falsch.

## Maschinenspezifische Konfiguration

Das Image ist für alle Geräte identisch. Die Abweichungen kommen nach `/etc`:

```nu
cd ~/projekte/noctarow
use scripts/noctarow.nu *
noctarow apply-host yoga920
swaymsg reload
```

Das legt ab:

| Quelle | Ziel |
|---|---|
| `hosts/yoga920/70-output.conf` | `/etc/sway/config.d/70-output.conf` |
| `hosts/yoga920/50-keyboard.conf` | `/etc/sway/config.d/50-keyboard.conf` |
| `hosts/yoga920/kanshi-config` | `~/.config/kanshi/config` |

Weil `/etc/sway/config.d/` in der Include-Kette **über**
`/usr/share/sway/config.d/` liegt, verdrängen die gleichnamigen Dateien die
Image-Defaults. Kein Merge, kein Konflikt.

## Was beim Image-Update passiert

```nu
sudo bootc upgrade
systemctl reboot
```

- `/usr` wird komplett ersetzt. Deine Defaults kommen in der neuen Version.
- `/etc` durchläuft den **3-Wege-Merge**: Basis (altes `/usr/etc`), aktueller
  Stand, neues `/usr/etc`. Selbst angelegte Dateien bleiben unangetastet.
- `~/.config` fasst niemand an.

Prüfen, was in `/etc` lokal abweicht:

```nu
sudo ostree admin config-diff | lines | parse "{status} {pfad}"
```

> [!warning] Den Merge-Test einmal bewusst durchspielen
> Vor einem Update, das `/usr`-Defaults ändert: Image v1 booten,
> `/etc/sway/config.d/50-keyboard.conf` anlegen, Image v2 mit geändertem
> `/usr`-Default bauen, `bootc upgrade`, rebooten, prüfen ob die lokale Datei
> überlebt hat. `bootc rollback` ist das Sicherheitsnetz, falls nicht — siehe
> [Rollback](#rollback) oben.
>
> Siehe auch [[docs/03-bauen-und-testen#Was ein nested Test nicht abdeckt]].

## Erstinbetriebnahme — Prüfliste

```nu
# Layout in allen drei Schichten
loadkeys -d                                    # TTY
localectl status                               # Greeter
noctarow keyboard-check                        # Sway-Session

# Skalierung
noctarow output-check

# Noctalia lebt
pgrep -a qs
systemctl --user status sway-session.target

# Beamer
# HDMI anstecken, dann:
swaymsg -t get_outputs | from json | select name active scale
journalctl --user -u kanshi -n 20
```

## Für die Flotte

| Maschine | Arch | Image-Tag | Host-Override |
|---|---|---|---|
| Yoga 920 | x86_64 | `stable` | `hosts/yoga920` |
| ASUS VivoBook X515JA | x86_64 | `44` (lokal) | `hosts/asus-x515ja` |
| Schulungs-PCs Intel/AMD | x86_64 | `stable` | noch anzulegen |
| Schulungs-PCs NVIDIA | x86_64 | `stable-nvidia` | eigener Build |

Ablauf, um für ein weiteres Gerät zu ermitteln, was einen eigenen
Host-Override braucht: [[docs/22-host-override-neue-hardware]].

Die NVIDIA-Variante braucht ein eigenes Containerfile mit
`akmod-nvidia`/`nvidia-driver` aus RPM Fusion — ein `FROM
quay.io/metarow/noctarow:stable` und darauf die Treiber-Schicht. Das ist ein
separates Image, kein Schalter.
