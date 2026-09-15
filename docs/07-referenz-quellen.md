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
| Terra (Fyra Labs), liefert `noctalia-legacy` + `noctalia-qs` | `repos.fyralabs.com/terra44`, gevendort als `terra.repo` |
| Quickshell (Fedora-Paket) | `dnf install quickshell` — **für Noctarow nicht verwendbar**, siehe Warnung |

> [!danger] Fedoras `quickshell` kollidiert mit `noctalia-qs`
> Noctalia v4 braucht den eigenen Quickshell-Fork `noctalia-qs`. Der liefert
> dieselben Provides wie Fedoras `quickshell` und ist **nicht gleichzeitig**
> installierbar. Für Noctarow gilt deshalb: `noctalia-legacy` über Terra
> installieren, das zieht `noctalia-qs` mit. **Kein `dnf install quickshell`.**
> Hergeleitet in [[docs/16-erkenntnisse-noctalia-container#`noctalia-qs` kollidiert mit Fedoras `quickshell`]].

> [!tip] `matugen` und `cliphist` brauchen kein COPR
> Beide liegen für aarch64 **und** x86_64 in den offiziellen Fedora-Repos und
> kommen ohnehin als Weak Dependencies von `noctalia-legacy` mit. Für ein
> bootc-Image, das jahrelang auf Schulungsrechnern bootet, ist das erheblich:
> COPRs geben weder Signatur- noch Lebensdauer-Zusagen. Genau deshalb ist die
> DisplayLink-COPR unten eine bewusst isolierte Ausnahme.

## DisplayLink / evdi (nur Dozenten-PC)

| Was | Wo |
|---|---|
| `displaylink` + `evdi` (COPR) | `copr.fedorainfracloud.org/coprs/crashdummy/Displaylink` |
| evdi upstream | `github.com/DisplayLink/evdi` |

Einzige COPR-Quelle im Projekt und bewusst nicht im Basis-Image, sondern im
abgeleiteten `Containerfile.displaylink`. Begründung:
[[docs/23-displaylink-evdi-dozenten-pc#Architekturentscheidung: evdi gehört NICHT ins Basis-Image]].

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
