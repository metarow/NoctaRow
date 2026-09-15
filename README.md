# Noctarow

Custom bootc/OCI-Image auf Basis von Fedora Sway Atomic 44.
Ziel-Registry: `quay.io/metarow/noctarow`
Primäre Zielhardware: Lenovo Yoga 920-13IKB (x86_64, 4K, Intel UHD 620)

Betreiber: MetaRow Software UG

> [!info] Brew-Integration umgesetzt, noch nicht per `bootc switch` aktiviert
> `noctalia-legacy` (Terra-Rename von `noctalia-shell`) kommt per `dnf`;
> `nushell`/`helix` kommen **nicht** mehr ins
> Image, sondern zur Laufzeit über Homebrew (`/var/home/linuxbrew`) —
> Login-Shell bleibt `bash`, `nushell` wird nur dem Terminal (foot) zugeordnet.
> Details in `docs/15-noctarow-basis-image.md`. Auf dem Yoga gebaut (rootless
> zur Verifikation, danach echter `sudo podman build` — beide erfolgreich,
> `bootc container lint`: 10/10 Checks, nur bekannte kosmetische Warnungen).
> Image liegt als `quay.io/metarow/noctarow:44-amd64` in root's
> `containers-storage`; der `bootc switch` selbst steht noch aus.
>
> Der Yoga 920 ist die erste und aktuell einzige Plattform für das
> Basis-Image — kein Cross-Build, kein Umweg über eine andere Maschine.

## Struktur

| Pfad | Zweck |
|---|---|
| `Containerfile` | Basis-Image-Definition |
| `Containerfile.displaylink` | abgeleitetes Image `FROM noctarow:44` mit evdi + DisplayLinkManager — nur für den Dozenten-PC, siehe `docs/23-displaylink-evdi-dozenten-pc.md` |
| `terra.repo` | gevendorte Terra-Repo-Datei (Quelle für Noctalia) |
| `overlay/` | spiegelt das Image 1:1, `COPY overlay/ /` im Build — Sway-Drop-ins, foot-Default, SDDM/vconsole, tmpfiles, Homebrew-Bootstrap (systemd-User-Unit + Skript), Terminal-Shell-Wrapper |
| `hosts/<name>/` | hostspezifische Overrides (Output, Tastatur, kanshi, Noctalia-Settings), per `noctarow apply-host <name>` — aktuell `yoga920`, `asus-x515ja`, `dozenten-pc` |
| `scripts/` | noctarow.nu (Build/Test/Push, `build-displaylink` für die abgeleitete Variante) |
| `docs/` | Projektnotizen, Index in `docs/README.md` |

## Grundsätze

- **Was alle brauchen, gehört ins Image; was nur diese Maschine braucht, nach
  `/etc`.** `rpm-ostree install` ist zum Bootstrappen erlaubt, aber temporär —
  Dauerlayer brechen den sauberen Update-Pfad.
- **System-weite Drop-ins** unter `/usr/share` bzw. `/etc`, keine
  `~/.config`-Dateien im Image.
- **Keine Top-Level-`~/.config/sway/config`** — Sway überspringt sonst die
  System-Default komplett (schwarzer Bildschirm).
- **Skalierung:** eDP-1 fraktional auf `scale 1.5` (XWayland-Unschärfe bewusst
  akzeptiert). Rückweg auf `scale 2`, falls eine Schulungsflotte Ziel wird.

## Bauen (auf dem Yoga, bash)

```bash
cd ~/projekte/noctarow
sudo podman build -t quay.io/metarow/noctarow:44-amd64 .
```

`sudo` ist zwingend: Das Image muss in root's `containers-storage` landen,
sonst findet `bootc switch --transport containers-storage` es nicht.

## Wechseln

```bash
sudo bootc switch --transport containers-storage quay.io/metarow/noctarow:44-amd64
sudo systemctl reboot
```

## Zurückrollen

```bash
sudo bootc rollback
sudo systemctl reboot
```

## Offen

- [ ] cosign-Signierung der Images
- [ ] QEMU-Vortest vor dem Bare-Metal-Boot
- [ ] Entscheidung: Terra (Drittanbieter) vs. `noctalia-qs` selbst bauen
- [ ] Entscheidung: v4 (`-legacy`) vs. v5-Track
- [ ] `bootc switch --transport containers-storage` + Reboot auf dem Yoga (Image liegt bereits gebaut in root's `containers-storage`)
- [ ] Erstlogin-Kontrolle nach dem Switch (Brew-Bootstrap, Terminal-Wrapper) — siehe `docs/15-noctarow-basis-image.md`
