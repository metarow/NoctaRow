---
titel: Deployment auf dem Lenovo Yoga 920
teil_von: "[[README]]"
tags: [bootc, deployment, yoga920, rebase, rollback]
zielgeraet: Lenovo Yoga 920-13IKB (x86_64)
---

# 06 — Deployment auf dem Lenovo Yoga 920

Das Yoga ist die erste echte Hardware. x86_64, unproblematisch — im Gegensatz
zum XPS, siehe [[docs/02-umgebung-wsl#Warum kein KVM auf diesem Gerät]].

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

> [!warning] Der Merge-Test gehört in die VM, nicht auf die Hardware
> Bevor du ein Update auf das Yoga lässt, spiel den Ablauf einmal in der
> Hyper-V-VM durch: Image v1 booten, `/etc/sway/config.d/50-keyboard.conf`
> anlegen, Image v2 mit geändertem `/usr`-Default bauen und pushen,
> `bootc upgrade`, rebooten, prüfen ob die lokale Datei überlebt hat.
>
> Siehe [[docs/03-bauen-und-testen#Stufe 3 — Hyper-V]].

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
| Schulungs-PCs Intel/AMD | x86_64 | `stable` | noch anzulegen |
| Schulungs-PCs NVIDIA | x86_64 | `stable-nvidia` | eigener Build |
| XPS 13 9345 | aarch64 | — | kein Deployment |

Die NVIDIA-Variante braucht ein eigenes Containerfile mit
`akmod-nvidia`/`nvidia-driver` aus RPM Fusion — ein `FROM
quay.io/metarow/noctarow:stable` und darauf die Treiber-Schicht. Das ist ein
separates Image, kein Schalter.
