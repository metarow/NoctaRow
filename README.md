# Noctarow

Custom bootc/OCI-Image auf Basis von Fedora Sway Atomic 44.
Ziel-Registry: `quay.io/metarow/noctarow`
Primäre Zielhardware: Lenovo Yoga 920-13IKB (x86_64, 4K, Intel UHD 620)

Betreiber: MetaRow Software UG

> [!info] Zielarchitektur vs. aktueller Stand
> Dieses `Containerfile` installiert aktuell `noctalia-shell`, `nushell` und
> `helix` alle per `dnf`. Geplant ist eine Brew-Integration: `nushell`/`helix`
> künftig zur Laufzeit über Homebrew (`/var/home/linuxbrew`) statt im Image,
> Details in `docs/15-noctarow-basis-image.md`. Bis diese Umstellung gebaut
> und verifiziert ist, gilt das hier beschriebene reine-dnf-Vorgehen.

## Struktur

| Pfad | Zweck |
|---|---|
| `Containerfile` | Image-Definition |
| `terra.repo` | gevendorte Terra-Repo-Datei (Quelle für Noctalia) |
| `sway/` | Sway-Drop-ins fürs Image (`/usr/share/sway/config.d/`) |
| `foot/foot.ini` | foot-System-Default (`/etc/xdg/foot/`) |
| `sddm/`, `tmpfiles/` | Login-Screen und First-Boot-Auslieferung |
| `hosts/yoga920/` | hostspezifische Overrides (Output, Tastatur, kanshi) |
| `scripts/` | noctarow.nu (Build/Test/Push) |

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

## Bauen (auf dem Yoga, Nushell)

```nu
cd ~/projekte/noctarow
sudo podman build -t quay.io/metarow/noctarow:44-amd64 .
```

`sudo` ist zwingend: Das Image muss in root's `containers-storage` landen,
sonst findet `bootc switch --transport containers-storage` es nicht.

## Wechseln

```nu
sudo bootc switch --transport containers-storage quay.io/metarow/noctarow:44-amd64
sudo systemctl reboot
```

## Zurückrollen

```nu
sudo bootc rollback
sudo systemctl reboot
```

## Offen

- [ ] cosign-Signierung der Images
- [ ] QEMU-Vortest vor dem Bare-Metal-Boot
- [ ] Entscheidung: Terra (Drittanbieter) vs. `noctalia-qs` selbst bauen
- [ ] Entscheidung: v4 (`-legacy`) vs. v5-Track
- [ ] Brew-Integration bauen und verifizieren (siehe `docs/15-noctarow-basis-image.md`)
