---
titel: Quellen und Upstream-Repos
teil_von: "[[README]]"
tags: [referenz, upstream]
---

# 07 — Quellen und Upstream

## Fedora Atomic Desktops

| Was | Wo |
|---|---|
| Image-Definition (Treefiles, `fedora-sericea.yaml`) | `pagure.io/workstation-ostree-config` |
| SIG, Issue-Tracker, Doku | `forge.fedoraproject.org/atomic-desktops` (Forgejo) |
| CI-Test-Builds (unsere Basis) | `gitlab.com/fedora/ostree/ci-test` |
| Registry | `quay.io/fedora-ostree-desktops/sway-atomic` |

> [!note] Kein offizielles GitHub-Repo
> Was auf GitHub liegt, sind Spiegel und Forks. Der `fedora-silverblue`-Org
> gehört nur ein Issue-Tracker für Silverblue.

## Sway auf Fedora

| Was | Wo |
|---|---|
| Fedora-Sway-Konfiguration (`sway-config-fedora`) | `gitlab.com/fedora/sigs/sway/sway-config-fedora` |
| `layered-include`, `sway-session.target` | Paket `sway-systemd`, upstream `github.com/alebastr/sway-systemd` |

Der Merge Request, der das Tastaturproblem upstream beheben soll, liegt gegen
`sway-config-fedora`. Bis er durch ist, ist unser Drop-in die Lösung.

## Noctalia / Quickshell

| Was | Wo |
|---|---|
| Noctalia-Shell | `github.com/noctalia-dev/noctalia-shell` |
| Quickshell | in Fedora paketiert: `dnf install quickshell` |

> [!tip] Kein COPR nötig
> `quickshell`, `matugen` und `cliphist` liegen für aarch64 **und** x86_64 in
> den offiziellen Fedora-Repos. Für ein bootc-Image, das jahrelang auf
> Schulungsrechnern bootet, ist das erheblich: COPRs geben weder Signatur- noch
> Lebensdauer-Zusagen.

## bootc

| Was | Wo |
|---|---|
| bootc | `containers.github.io/bootc/` |
| bootc-image-builder | `quay.io/centos-bootc/bootc-image-builder` |

## Dell XPS 13 9345 (nur zur Einordnung)

Kein Deployment-Ziel. Für den Fall, dass sich das ändert:

- Firmware seit März 2026 upstream in `linux-firmware`
- `dell-xps-ec`-Treiber (Lüfter, Thermik, Suspend) von Aleksandrs Vinarskis
- Kernel-Repo: `linux-x1e80100-dell-tributo`
- DTB: `x1e80100-dell-xps13-9345.dtb`
- Linux bootet auf EL1 → **kein KVM**

Stock-Fedora-aarch64 endet auf diesem Gerät berichteterweise im Bootloop.
