---
title: Noctarow
projekt: Noctarow
firma: MetaRow Software UG
basis: quay.io/fedora-ostree-desktops/sway-atomic:44
registry: quay.io/metarow/noctarow
architekturen: [x86_64, aarch64]
status: in Entwicklung
erstellt: 2026-07-09
tags: [bootc, fedora, sway, noctalia, quickshell, wsl, nushell]
---

# Noctarow

Ein bootc-Image auf Basis von **Fedora Sway Atomic**, erweitert um die
**Noctalia**-Shell (Quickshell), mit korrekter Tastaturkonfiguration und
HiDPI-Unterstützung. Gebaut für die Schulungsflotte der MetaRow Software UG.

> [!info] Namensherkunft
> **Noct**alia + Meta**Row**. Image-Referenz: `quay.io/metarow/noctarow:44`

## Dokumentation

- [[docs/01-erkenntnisse|01 — Erkenntnisse: Wie Fedora Sway konfiguriert wird]]
- [[docs/02-umgebung-wsl|02 — Arbeitsumgebung: Fedora WSL, Nushell, Helix]]
- [[docs/03-bauen-und-testen|03 — Image bauen und nested testen]]
- [[docs/04-quay-veroeffentlichung|04 — Veröffentlichung auf quay.io]]
- [[docs/05-hidpi-und-monitore|05 — HiDPI, Skalierung, Beamer]]
- [[docs/06-lenovo-yoga-deployment|06 — Deployment auf dem Lenovo Yoga 920]]
- [[docs/07-referenz-quellen|07 — Quellen und Upstream-Repos]]
- [[docs/08-verteilung|08 — Verteilung: was liegt auf Windows, was in WSL]]

## Verzeichnisstruktur

```
noctarow/
├── Containerfile              # Multi-Stage Build
├── sway/                      # Drop-ins → /usr/share/sway/config.d/
│   ├── 50-keyboard.conf
│   ├── 60-noctalia.conf
│   ├── 70-output.conf
│   ├── 90-bar.conf            # leer: verdrängt swaybar
│   └── 90-swayidle.conf       # leer: verdrängt swayidle
├── sddm/                      # Display-Manager: Tastatur + HiDPI
├── tmpfiles/                  # First-Boot-Auslieferung der User-Config
├── hosts/                     # maschinenspezifisch → /etc/sway/config.d/
│   ├── yoga920/
│   └── xps13/
├── scripts/
│   ├── noctarow.nu            # Build/Test/Disk/Push  → WSL (ext4!)
│   ├── noctarow-win.nu        # WSL- + Hyper-V-Steuerung → Windows
│   └── bootstrap-noctarow.nu  # einmalige Einrichtung, auf Windows
└── docs/
```

## Einrichtung

Einmalig, in Nushell **auf Windows**, im Download-Ordner:

```nu
nu bootstrap-noctarow.nu --distro FedoraLinux-44 --user fritz
```

Das Skript entpackt das Archiv nach `~/projekte/noctarow` in der WSL-Distro,
prüft das Dateisystem, legt einen initialen Git-Commit an und kopiert
`noctarow-win.nu` in dein Windows-Nushell-Verzeichnis.

Details: [[docs/08-verteilung]]

## Schnellstart

In der Fedora-WSL-Distro, Nushell:

```nu
use scripts/noctarow.nu *

noctarow build
noctarow test-nested        # Sway + Noctalia als Fenster auf dem Windows-Desktop
noctarow keyboard-check     # prüft das aktive XKB-Layout
```

## Kernaussage in drei Sätzen

Fedora Sway liest die Tastaturbelegung **nicht** aus `localectl`. Das Image
liefert nirgendwo einen `input`-Block, und die Datei, die das in der
Live-Umgebung erledigt, existiert im installierten System nicht. Deshalb ist
ein eigenes Drop-in kein Workaround, sondern die einzig vorgesehene Lösung.

Details: [[docs/01-erkenntnisse]]
