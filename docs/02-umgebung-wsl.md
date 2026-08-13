---
titel: Arbeitsumgebung — Fedora WSL, Nushell, Helix
teil_von: "[[README]]"
tags: [wsl, nushell, helix, podman, fedora]
host: Dell XPS 13 9345 (Snapdragon X Elite, aarch64)
---

# 02 — Arbeitsumgebung

## Warum Fedora WSL und nicht Podman Desktop

`podman.exe` unter Windows ist **nur ein Client**. Es gibt keine
Container-Engine unter Windows; `podman machine init` legt im Hintergrund eine
eigene WSL2-Appliance an. Die ist als Blackbox gebaut, nicht als
Arbeitsumgebung — kein WSLg-Zugang, kein Editor, kein Home.

Unser Workflow braucht `dnf`, GUI-Zugriff über WSLg und später privilegierte
Container mit Loop-Devices. Also: **eine Fedora-WSL-Distro, Podman darin.**

Die arm64-CLI von Podman ist trotzdem ein gutes Zeichen — sie belegt, dass
Podman ernsthaft für Windows-on-ARM baut.

## Warum kein KVM auf diesem Gerät

Auf Snapdragon-X-Geräten übergibt die Firmware den Linux-Kernel auf **EL1
statt EL2**. Damit gibt es unter Linux kein `/dev/kvm`. Windows kommt über
einen proprietären Shim nach EL2 — deshalb funktionieren WSL2 und Hyper-V,
Linux-natives KVM auf demselben Gerät aber nicht.

> [!note] Praktische Folge
> Virtualisierung auf dem XPS läuft **über Windows**, nicht unter Linux.
> WSL2 zum Bauen, Hyper-V zum Booten des Images.

## Basis-Setup

### Vorhandene Distros bereinigen

> [!danger] `wsl --unregister` ist endgültig
> Kein Papierkorb, keine Rückfrage. Vorher exportieren.

Auf Windows, Nushell:

```nu
let sicherung = ($nu.home-path | path join "wsl-backup")
mkdir $sicherung

wsl --export Ubuntu-24.04        ($sicherung | path join "ubuntu-2404.tar")
wsl --export openSUSE-Tumbleweed ($sicherung | path join "tumbleweed.tar")
```

> [!warning] `$env.HOME` gibt es auf Windows nicht
> Dort heißt die Variable `USERPROFILE`. `$nu.home-path` funktioniert auf
> beiden Seiten. Entsprechend liegt der Nushell-Konfigurationsordner auf
> Windows unter `%APPDATA%\nushell`, nicht unter `~/.config` —
> `$nu.default-config-dir` liefert ihn plattformneutral.

Docker Desktop **zuerst über Windows deinstallieren**, nicht per
`wsl --unregister` — sonst bleiben Dienste und Registry-Einträge zurück:

```nu
winget uninstall Docker.DockerDesktop
wsl --list
```

Erst dann die Reste:

```nu
wsl --unregister docker-desktop
wsl --unregister docker-desktop-data
wsl --unregister Ubuntu-24.04
wsl --unregister openSUSE-Tumbleweed
wsl --unregister Python
```

Aufräumen: `%LOCALAPPDATA%\Docker`, `%PROGRAMDATA%\DockerDesktop`.

### Fedora installieren

Fedora ist seit Fedora 42 offizielle WSL-Distro und wird auch für aarch64
gebaut — die ARM-Images sind allerdings noch als BETA markiert.

```nu
wsl --update
wsl --install FedoraLinux-44
wsl --set-default FedoraLinux-44
```

Beim ersten Start: Benutzername angeben. Der Account landet in `wheel`, hat
aber **kein Passwort** — `sudo` läuft passwortlos. Wenn das nicht gewünscht
ist: `passwd` setzen und `/etc/sudoers.d/wsluser` löschen.

### wsl.conf — systemd und shared mounts

`/etc/wsl.conf`:

```ini
[boot]
systemd=true
command="mount --make-rshared /"

[interop]
enabled=true
appendWindowsPath=true
```

> [!important] `mount --make-rshared /`
> WSL mountet `/` als `private`. Das ist kein kosmetisches Problem —
> `bootc-image-builder` reicht Loop-Devices und Bind-Mounts durch und
> scheitert sonst.

Danach auf Windows `wsl --shutdown`, neu starten, gegenprüfen:

```nu
findmnt -o TARGET,PROPAGATION /       # muss "shared" zeigen
podman info --format '{{.Host.CgroupControllers}}'   # [cpu memory pids]
```

## Werkzeuge installieren

```bash
sudo dnf upgrade --refresh
sudo dnf install -y podman buildah skopeo jq git-core \
                    qemu-img gawk util-linux-user
```

> [!warning] Das Fedora-WSL-Image ist minimal
> Es bringt **kein `awk`** mit, kein `chsh` (Paket `util-linux-user`) und kein
> `qemu-img`. Rechne damit, dass weitere Selbstverständlichkeiten fehlen.
> Unsere Skripte kommen deshalb ohne `awk` aus (`df --output=fstype` statt
> `df -T | awk`).

### Nushell und Helix

Beide liegen in den **offiziellen Fedora-Repos**, auch für aarch64. Kein COPR:

```bash
sudo dnf install -y nushell helix
```

Verifiziert am 2026-07-09 gegen Fedora 44 aarch64.

> [!tip] Warum das mehr als Bequemlichkeit ist
> Damit stehen beide auch für ein späteres Werkzeug- oder Toolbox-Image zur
> Verfügung, ohne eine Fremdquelle in die Vertrauenskette zu holen. Dieselbe
> Überlegung wie bei `quickshell` — siehe [[docs/07-referenz-quellen]].

### Nushell als Login-Shell

`chsh` liegt auf Fedora im Paket `util-linux-user`, das im WSL-Image fehlt:

```nu
sudo dnf install -y util-linux-user

let nupfad = (which nu | get path.0)
$nupfad | sudo tee -a /etc/shells
chsh -s $nupfad
```

Dann auf Windows `wsl --shutdown`, neu starten.

> [!danger] Der Rückweg — merken, bevor du ihn brauchst
> ```nu
> wsl -d FedoraLinux-44 -e /bin/bash
> ```
> `-e` umgeht die Login-Shell vollständig. Damit kommst du auch dann in die
> Distro, wenn deine `config.nu` beim Start abstürzt. Zurückschalten mit
> `chsh -s /bin/bash`.

> [!warning] Nushell liest kein `/etc/profile`
> Und auch kein `/etc/profile.d/*.sh`. Was Fedora dort an `PATH`-Erweiterungen
> und Umgebungsvariablen ablegt, kommt nicht an. Bei einer WSL-Distro
> überschaubar, aber nicht null — wenn ein Werkzeug plötzlich „not found" ist,
> ist das die erste Verdächtige.
>
> Ebenso erwarten manche Tools eine POSIX-Login-Shell; der VS-Code-Remote-Server
> ist der bekannteste Fall.

> [!note] Unsere Skripte sind davon nicht betroffen
> `nw run` ruft `wsl -d … -- nu -c "…"` auf, der Bootstrap nutzt
> `wsl … -- sh -c "…"`. Beide nennen die Shell **explizit**. Ein Wechsel der
> Login-Shell ändert daran nichts.

### Nushell-Konfiguration

`~/.config/nushell/env.nu`:

```nu
$env.EDITOR = "hx"
$env.VISUAL = "hx"

# Registry-Login überlebt sonst keinen WSL-Neustart, weil XDG_RUNTIME_DIR
# bei jedem Start neu angelegt wird.
$env.REGISTRY_AUTH_FILE = ($nu.home-path | path join ".config/containers/auth.json")

# noctarow-Modul von überall importierbar
$env.NU_LIB_DIRS = ($env.NU_LIB_DIRS | append "/home/fritz/projekte/noctarow")
```

`~/.config/nushell/config.nu`:

```nu
$env.config.show_banner = false
use scripts/noctarow.nu *
```

> [!caution] `WLR_RENDERER` nicht global setzen
> Es gehört in den Container, und dort setzt es `noctarow test-nested` bereits.
> Global in `env.nu` beeinflusst es jede wlroots-Anwendung, die du je in WSL
> startest — und du suchst später lange, warum nichts beschleunigt läuft.

### Helix — Sprachserver

Für die Projektarbeit relevant: YAML, Markdown, Bash.

```bash
sudo dnf install -y yaml-language-server marksman
hx --health
```

## Prüfliste

```nu
# Windows-Seite
wsl --list --verbose

# WSL-Seite, Nushell
findmnt -o TARGET,PROPAGATION /
podman info --format '{{.Host.CgroupControllers}}'
podman info | lines | find -i rootless
echo $env.WAYLAND_DISPLAY          # wayland-0
ls /mnt/wslg/runtime-dir/          # Wayland-Socket muss existieren
```

> [!info] Der WSLg-Symlink ist eine Falle
> `$XDG_RUNTIME_DIR/wayland-0` ist ein **Symlink** auf
> `/mnt/wslg/runtime-dir/wayland-0`. Wer den Symlink-Pfad in einen Container
> bind-mountet, mountet ein totes Ziel — der Container sieht `/mnt/wslg`
> nicht. Immer den **Zielpfad** mounten.
