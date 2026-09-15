---
title: Noctarow
projekt: Noctarow
firma: MetaRow Software UG
basis: quay.io/fedora-ostree-desktops/sway-atomic:44
registry: quay.io/metarow/noctarow
architekturen: [x86_64]
status: im Betrieb auf zwei Geraeten, Registry-Verteilung offen
erstellt: 2026-07-09
tags: [bootc, fedora, sway, noctalia, quickshell, nushell, homebrew]
---

# Noctarow

Ein bootc-Image auf Basis von **Fedora Sway Atomic**, erweitert um die
**Noctalia**-Shell (Quickshell), mit korrekter Tastaturkonfiguration und
HiDPI-Unterstützung. Gebaut für die Schulungsflotte der MetaRow Software UG.

> [!info] Namensherkunft
> **Noct**alia + Meta**Row**. Geplante Image-Referenz:
> `quay.io/metarow/noctarow:44`. Die Registry ist derzeit noch leer, jede
> Maschine baut lokal — siehe [[docs/04-quay-veroeffentlichung]].

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
- [[docs/15-noctarow-basis-image|15 — Basis-Image mit Brew-Integration (umgesetzt, im Betrieb)]]
- [[docs/16-erkenntnisse-noctalia-container|16 — Erkenntnisse: Noctalia, Container, Nushell]]
- [[docs/18-autostart-nextcloud-sway|18 — Autostart: Nextcloud unter Sway]]
- [[docs/19-flatpak-auf-sway-atomic|19 — Flatpak auf Sway Atomic]]
- [[docs/20-sway-referenz|20 — Sway-Referenz]]
- [[docs/21-sway-titelleiste-ausblenden|21 — Sway-Titelleiste ausblenden]]
- [[docs/22-host-override-neue-hardware|22 — Host-Override für neue Hardware anlegen]]
- [[docs/23-displaylink-evdi-dozenten-pc|23 — DisplayLink/evdi: abgeleitetes Image für den Dozenten-PC]]
- [[docs/24-noctarow-noctalia-handover|24 — Noctalia startet nicht: Diagnose, Fix, Rollout-Falle]]

Lücken in der Nummerierung (02, 08, 11, 17) sind historisch und bleiben —
ein Umsortieren bräche Links und Git-Historie ohne Gewinn.

### Archiv (Hyprland-Vorläufer, technisch weiter gültig)

- [[docs/archiv/nushell-installieren|Nushell installieren — generischer Fedora-Spickzettel]]
- [[docs/archiv/noctalia-starten|Noctalia starten — Quickshell-IPC, Runner-Kopplung]]

Beide Notizen stammen aus der Zeit vor der Sway-Entscheidung. Ihre
Querverweise zeigen in den Hyprland-Vault und sind hier als Klartext
belassen.

## Verzeichnisstruktur

```
noctarow/
├── Containerfile               # Basis-Image; COPY overlay/ / -- spiegelt das Image 1:1
├── Containerfile.displaylink   # abgeleitet FROM noctarow:44, evdi + DisplayLinkManager (nur Dozenten-PC)
├── terra.repo                  # gevendort, excludepkgs=terra-obsolete
├── overlay/
│   ├── etc/xdg/foot/foot.ini           # shell=Terminal-Wrapper, font erhalten
│   └── usr/
│       ├── share/
│       │   ├── sway/config.d/          # 30-borders … 95-noctalia
│       │   └── noctarow/environment.noctarow   # wird an /etc/sway/environment angehaengt
│       ├── lib/
│       │   ├── sddm/sddm.conf.d/10-noctarow.conf
│       │   ├── vconsole.conf.noctarow  # Quelle fuer tmpfiles-Typ C
│       │   ├── tmpfiles.d/
│       │   │   ├── noctarow.conf       # First-Boot-Auslieferung User-Config
│       │   │   └── homebrew.conf       # /var/home/linuxbrew vorab, User-owned
│       │   └── systemd/user/homebrew-bootstrap.service
│       └── libexec/noctarow/
│           ├── homebrew-bootstrap.sh   # Installer + nushell/helix via brew
│           └── terminal-shell          # Wrapper: nu aus brew, sonst bash
├── hosts/                      # maschinenspezifisch → /etc/sway/config.d/, per `noctarow apply-host <name>`
│   ├── yoga920/                # 4K-Laptop, scale 1.5, kanshi-Profile
│   ├── asus-x515ja/            # 15,6" FHD, scale 1.3
│   └── dozenten-pc/            # Desktop, DisplayLink -> laeuft auf noctarow-displaylink
├── scripts/
│   └── noctarow.nu             # build / build-displaylink / test-nested / to-root / push / apply-host
└── docs/
    ├── 01 … 24                 # Projektnotizen, nummeriert (Luecken historisch)
    └── archiv/                 # Hyprland-Vorlaeufer
```

## Einrichtung

Jedes Flottengerät ist Build- **und** Zielmaschine — kein Cross-Build, kein
Windows-/WSL-Umweg. Login-Shell ist bash; `git clone` direkt auf dem Gerät:

```bash
git clone https://github.com/metarow/NoctaRow.git ~/Projekte/NoctaRow
cd ~/Projekte/NoctaRow
```

Details zum Buildumgebungs-Setup: [[docs/09-yoga-buildumgebung]] (am Yoga
protokolliert, gilt für jedes x86_64-Gerät der Flotte)

## Schnellstart

Nushell steht als Terminal-Default zur Verfügung (Homebrew-Installation,
siehe [[docs/15-noctarow-basis-image]]) — Build-Kommandos laufen darin:

```nu
use scripts/noctarow.nu *

noctarow build              # Basis-Image
noctarow build-displaylink  # abgeleitete Variante, nur Dozenten-PC
noctarow test-nested        # Sway + Noctalia in einem nested Fenster, hardwarebeschleunigt
noctarow keyboard-check     # prüft das aktive XKB-Layout
```

## Kernaussage in drei Sätzen

Fedora Sway liest die Tastaturbelegung **nicht** aus `localectl`. Das Image
liefert nirgendwo einen `input`-Block, und die Datei, die das in der
Live-Umgebung erledigt, existiert im installierten System nicht. Deshalb ist
ein eigenes Drop-in kein Workaround, sondern die einzig vorgesehene Lösung.

Details: [[docs/01-erkenntnisse]]
