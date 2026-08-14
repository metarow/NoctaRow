---
title: Noctarow
projekt: Noctarow
firma: MetaRow Software UG
basis: quay.io/fedora-ostree-desktops/sway-atomic:44
registry: quay.io/metarow/noctarow
architekturen: [x86_64]
status: in Entwicklung
erstellt: 2026-07-09
tags: [bootc, fedora, sway, noctalia, quickshell, nushell, homebrew]
---

# Noctarow

Ein bootc-Image auf Basis von **Fedora Sway Atomic**, erweitert um die
**Noctalia**-Shell (Quickshell), mit korrekter Tastaturkonfiguration und
HiDPI-Unterstützung. Gebaut für die Schulungsflotte der MetaRow Software UG.

> [!info] Namensherkunft
> **Noct**alia + Meta**Row**. Image-Referenz: `quay.io/metarow/noctarow:44`

## Dokumentation

- [[docs/01-erkenntnisse|01 — Erkenntnisse: Wie Fedora Sway konfiguriert wird]]
- [[docs/03-bauen-und-testen|03 — Image bauen und nested testen]]
- [[docs/04-quay-veroeffentlichung|04 — Veröffentlichung auf quay.io]]
- [[docs/05-hidpi-und-monitore|05 — HiDPI, Skalierung, Beamer]]
- [[docs/06-lenovo-yoga-deployment|06 — Deployment auf dem Lenovo Yoga 920]]
- [[docs/07-referenz-quellen|07 — Quellen und Upstream-Repos]]
- [[docs/09-yoga-buildumgebung|09 — Yoga-Buildumgebung: Setup-Log]]
- [[docs/10-github-repository|10 — GitHub-Repository und CI]]
- [[docs/12-noctalia-layering-explorationsweg|12 — Noctalia per rpm-ostree-Layering (Explorationsweg)]]
- [[docs/13-leitfaden-atomic-brew-homebrew|13 — Leitfaden: bootc-Image mit Homebrew (Vorarbeit)]]
- [[docs/14-troubleshooting-atomic-brew|14 — Troubleshooting-Log: atomic-brew]]
- [[docs/15-noctarow-basis-image|15 — Zielarchitektur: Basis-Image mit Brew-Integration (aktiver Plan)]]
- [[docs/16-erkenntnisse-noctalia-container|16 — Erkenntnisse: Noctalia, Container, Nushell]]
- [[docs/18-autostart-nextcloud-sway|18 — Autostart: Nextcloud unter Sway]]
- [[docs/19-flatpak-auf-sway-atomic|19 — Flatpak auf Sway Atomic]]
- [[docs/20-sway-referenz|20 — Sway-Referenz]]
- [[docs/21-sway-titelleiste-ausblenden|21 — Sway-Titelleiste ausblenden]]
- [[docs/displaylink-evdi-sway-atomic-zusammenfassung|DisplayLink/evdi auf Sway Atomic — Ergebnis]]

### Weitere Referenzen (Hyprland-Vorläufer, technisch weiter gültig)

- [[docs/01-nushell-installieren|Nushell installieren — generischer Fedora-Spickzettel]]
- [[docs/Noctalia starten|Noctalia starten — Quickshell-IPC, Runner-Kopplung]]

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
│   └── yoga920/
├── scripts/
│   └── noctarow.nu            # Build/Test/Push, nativ auf dem Yoga
└── docs/
```

## Einrichtung

Der Yoga ist Build- **und** Zielmaschine — kein Windows-/WSL-Umweg. Login-Shell
ist bash; `git clone` direkt auf dem Yoga:

```bash
git clone https://github.com/metarow/noctarow.git ~/projekte/noctarow
cd ~/projekte/noctarow
```

Details zum Buildumgebungs-Setup: [[docs/09-yoga-buildumgebung]]

## Schnellstart

Nushell steht als Terminal-Default zur Verfügung (Homebrew-Installation,
siehe [[docs/15-noctarow-basis-image]]) — Build-Kommandos laufen darin:

```nu
use scripts/noctarow.nu *

noctarow build
noctarow test-nested        # Sway + Noctalia in einem nested Fenster, hardwarebeschleunigt
noctarow keyboard-check     # prüft das aktive XKB-Layout
```

## Kernaussage in drei Sätzen

Fedora Sway liest die Tastaturbelegung **nicht** aus `localectl`. Das Image
liefert nirgendwo einen `input`-Block, und die Datei, die das in der
Live-Umgebung erledigt, existiert im installierten System nicht. Deshalb ist
ein eigenes Drop-in kein Workaround, sondern die einzig vorgesehene Lösung.

Details: [[docs/01-erkenntnisse]]
