# Noctarow

Custom bootc/OCI-Image auf Basis von Fedora Sway Atomic 44.
Ziel-Registry: `quay.io/metarow/noctarow` (angelegt, aber noch leer)
Zielhardware: x86_64-Flotte der MetaRow Software UG, aktuell drei Geräte,
siehe `docs/06-lenovo-yoga-deployment.md#für-die-flotte`

Betreiber: MetaRow Software UG

> [!info] Stand: im Betrieb, Verteilung noch lokal
> `noctalia-legacy` (Terra-Rename von `noctalia-shell`) kommt per `dnf`.
> `nushell`/`helix` kommen **nicht** ins Image, sondern zur Laufzeit über
> Homebrew (`/var/home/linuxbrew`). Login-Shell bleibt `bash`, `nushell` ist
> nur dem Terminal (foot) zugeordnet. Details in
> `docs/15-noctarow-basis-image.md`.
>
> Ausgerollt und live verifiziert: **ASUS X515JA** (2026-08-25, per
> `bootc upgrade`) und **Dozenten-PC** (2026-09-15, auf der abgeleiteten
> DisplayLink-Variante). Für den **Yoga 920** ist kein Switch belegt.
>
> **Jede Maschine baut bisher selbst** und schaltet über
> `--transport containers-storage` um. Die Registry ist noch leer, ein
> `bootc switch quay.io/metarow/noctarow:stable` funktioniert daher **nicht**.
> Solange das so ist, gibt es keinen gemeinsamen Flottenstand, nur drei
> lokale Builds. Siehe „Offen" unten.

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
- **Skalierung:** Der Image-Default ist bewusst konservativ `output * scale 1`,
  damit unbekannte Hardware startet. Abweichungen sind hostspezifisch und
  liegen in `hosts/<name>/70-output.conf`, etwa `scale 1.5` auf dem 4K-Yoga
  und `scale 1.3` auf dem ASUS. Hintergrund: `docs/05-hidpi-und-monitore.md`.

## Bauen (auf der Zielmaschine selbst, Nushell)

Jede Maschine ist zugleich Build- und Zielmaschine, es gibt keinen
Cross-Build und keine zentrale Build-Maschine.

```nu
use scripts/noctarow.nu *

noctarow doctor                  # Umgebung prüfen
noctarow build                   # Basis-Image, rootless
noctarow build-displaylink       # nur Dozenten-PC, setzt den Basis-Build voraus
noctarow to-root                 # rootless -> root's containers-storage
```

`to-root` ist nötig, weil `bootc switch --transport containers-storage` als
root läuft und deshalb nur `/var/lib/containers/storage` sieht. Für die
abgeleitete Variante `noctarow to-root --image noctarow-displaylink`.

## Wechseln

```bash
sudo bootc switch --transport containers-storage localhost/noctarow:44
sudo systemctl reboot
```

> [!warning] Gleiche Referenz, neuer Inhalt: `switch` ist ein No-Op
> Läuft die Maschine schon auf genau dieser Referenz, meldet `switch`
> „Image specification is unchanged." und tut nichts. Dann `sudo bootc upgrade`
> verwenden. Am ASUS reproduziert, siehe
> `docs/06-lenovo-yoga-deployment.md#umschalten`.

## Zurückrollen

```bash
sudo bootc rollback
sudo systemctl reboot
```

## Offen

Die ersten drei Punkte blockieren den Flottenbetrieb, alles andere ist
Komfort.

- [ ] **Images nach quay.io pushen.** `quay.io/metarow/noctarow` ist angelegt,
      aber ohne Tags. Bis dahin baut jede Maschine selbst und `:stable` aus
      `docs/06` existiert nicht. Ablauf: `docs/04-quay-veroeffentlichung.md`
- [ ] **`LICENSE` anlegen.** Das GitHub-Repo ist öffentlich, eine Lizenzdatei
      fehlt. Vorlage in `docs/10-github-repository.md#schritt-2`
- [ ] **CI entscheiden.** `docs/10` beschreibt einen Multi-Arch-Workflow,
      `docs/04` stellt Multi-Arch zurück, `.github/` existiert nicht.
      Widerspruch auflösen, dann eins von beidem umsetzen
- [ ] cosign-Signierung der Images
- [ ] QEMU-Vortest vor dem Bare-Metal-Boot
- [ ] Entscheidung: Terra (Drittanbieter) vs. `noctalia-qs` selbst bauen
- [ ] Entscheidung: v4 (`-legacy`) vs. v5-Track — Stand geprüft, v5 ist noch
      Beta, siehe `docs/24-noctarow-noctalia-handover.md#6`
- [ ] Yoga 920 auf den aktuellen Stand bringen, für ihn ist kein Switch belegt
- [ ] `--tag`/`--noctalia-ref` in `scripts/noctarow.nu` ziehen nicht: der
      Basis-`Containerfile` hat kein `ARG`, `FROM …:44` ist fest verdrahtet.
      Entweder `ARG` ergänzen oder die Flags entfernen
