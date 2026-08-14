---
titel: Noctarow-Basis-Image — atomic-brew als Ausgangspunkt
aliases: [Basis-Image-Entwurf, atomic-brew-Merge]
teil_von: "[[README]]"
tags: [bootc, podman, homebrew, sway, noctalia, nushell, terra, containerfile, bash]
zielgeraet: Lenovo Yoga 920-13IKB (x86_64) — erste und aktuell einzige Plattform für das Basis-Image
erstellt: 2026-08-02
status: aktiver Plan — Containerfile im Repo-Root noch nicht umgestellt
---

# 15 — Noctarow-Basis-Image: atomic-brew + Noctarow-Konfiguration

> [!important] Aktiver Plan, Containerfile noch nicht umgestellt
> Der `Containerfile` im Repo-Root macht aktuell noch reines `dnf install
> noctalia-shell nushell helix` — die hier beschriebene Brew-Integration ist
> als **nächster Bauversuch bestätigt**, aber noch nicht umgesetzt. Bis zum
> Umbau bleibt das reale Containerfile die Wahrheit für das, was tatsächlich
> läuft.
>
> **Live-Stand auf dem Yoga** (verifiziert 2026-08-14): Login-Shell ist
> bereits `bash`. Homebrew ist bereits bootstrapped
> (`/home/linuxbrew/.linuxbrew/bin/brew` vorhanden, Eigentümer `fritz`), aber
> `brew list` ist leer — `nushell`/`helix` stehen noch aus. Das System läuft
> auf dem reinen Upstream-Basisimage
> (`quay.io/fedora-ostree-desktops/sway-atomic:44`) mit `rpm-ostree`-Layern
> `noctalia-shell` + `terra-release` — noch **kein** eigenes bootc-Image, noch
> kein `bootc switch` durchgeführt. Genau der Zustand „Basis-Image mit
> angepasster Konfiguration", den diese Note als Ausgangspunkt voraussetzt.

> [!important] Neues Vorgehen — überschreibt alte Annahmen
> 1. **nushell und helix kommen ausschließlich über Homebrew** nach
>    `/var/home/linuxbrew` — sie sind **nicht** Teil des Basis-Images.
> 2. **nushell wird nie Login-Shell.** Die Zuordnung geschieht in der
>    Terminal-Konfiguration (foot).
> 3. **Die Buildumgebung nutzt ausschließlich bash-Befehle.** Alle
>    Code-Blöcke in dieser Note sind bash; Nushell existiert auf dem
>    frisch geswitchten System erst nach dem Brew-Bootstrap.
>
> Damit gilt wieder der originale atomic-brew-Schnitt: Image = Basis +
> Toolchain + Noctalia-Konfiguration; Userland-Werkzeuge = brew in `/var`.

Zusammengeführt werden:

1. **atomic-brew** ([[docs/13-leitfaden-atomic-brew-homebrew]], Fehlerlog in
   [[docs/14-troubleshooting-atomic-brew]]): Build-Toolchain read-only in
   `/usr`, Homebrew zur Laufzeit in `/var/home/linuxbrew`, tmpfiles-Regel
   gegen die sudo-Falle des Installers, systemd-User-Unit als
   Erstinstallation, `COPY overlay/ /` als Strukturprinzip.
2. **Noctarow-Konfiguration** ([[docs/09-yoga-buildumgebung]] + Noctalia-
   Integration): Terra gevendort, `noctalia-shell` per dnf, Sway-Drop-in-
   Kette, foot-Default, SDDM-HiDPI, Guard gegen `terra-obsolete`.

> [!note] Bewusst akzeptierter Trade-off
> brew liefert „latest zum Installationszeitpunkt" — auf mehreren Geräten
> potenziell unterschiedliche nushell/helix-Versionen. Das ist mit dem
> neuen Vorgehen akzeptiert; dafür bleiben beide Tools unabhängig vom
> Image-Lebenszyklus aktuell und `bootc rollback` fasst sie nie an.

> [!note] Basis bleibt `sway-atomic:44`, nicht Hyprland
> Ein offizielles Hyprland-Atomic-Image aus `fedora-ostree-desktops`
> existiert nicht. Hyprland bleibt ein eigenes Modul/eigene Rolle in der
> Rollen-Matrix — nicht Teil dieses Basis-Images.

## Repo-Struktur

Strukturänderung gegenüber [[docs/09-yoga-buildumgebung]]: Die einzelnen
`COPY`-Zeilen weichen dem **Overlay-Prinzip** aus atomic-brew — ein
`COPY overlay/ /`, das Git-Layout spiegelt das Image 1:1.

```bash
mkdir -p overlay/usr/share/sway/config.d \
         overlay/usr/share/noctarow \
         overlay/usr/lib/tmpfiles.d \
         overlay/usr/lib/systemd/user \
         overlay/usr/libexec/noctarow \
         overlay/usr/lib/sddm/sddm.conf.d \
         overlay/etc/xdg/foot
```

| Pfad | Zweck |
|---|---|
| `Containerfile` | Image-Definition (unten) |
| `terra.repo` | gevendort, **mit `excludepkgs=terra-obsolete`** |
| `overlay/usr/share/sway/config.d/` | 30-borders, 50-keyboard, 70-output, leere 90-bar/90-swayidle, 95-noctalia |
| `overlay/usr/share/noctarow/environment.noctarow` | wird im Build an `/etc/sway/environment` **angehängt** |
| `overlay/usr/lib/tmpfiles.d/homebrew.conf` | `/var/home/linuxbrew` vorab, User-owned |
| `overlay/usr/lib/systemd/user/homebrew-bootstrap.service` | Erstinstallation |
| `overlay/usr/libexec/noctarow/homebrew-bootstrap.sh` | Installer + nushell/helix/Leaf-Tools |
| `overlay/usr/libexec/noctarow/terminal-shell` | Terminal-Shell-Wrapper (nu, sonst bash) |
| `overlay/etc/xdg/foot/foot.ini` | System-Default, Shell-Zuordnung über den Wrapper |
| `overlay/usr/lib/sddm/sddm.conf.d/` | HiDPI + Tastatur |
| `hosts/yoga920/`, `scripts/` | unverändert aus dem Bestand |

## Die Dateien

### `terra.repo`

Wie gevendort, plus die Lehre aus dem `terra-obsolete`-Vorfall. Ohne
nushell im Image ist die Obsoletes-Falle entschärft, der Ausschluss bleibt
trotzdem drin — Terra soll grundsätzlich keine Metapaket-Umleitungen in
den Build tragen:

```bash
cat > terra.repo << 'EOF'
[terra]
name=Terra $releasever
baseurl=https://repos.fyralabs.com/terra$releasever
type=rpm
skip_if_unavailable=False
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://repos.fyralabs.com/terra$releasever/key.asc
enabled=1
enabled_metadata=1
metadata_expire=4h
excludepkgs=terra-obsolete
EOF
```

### `overlay/usr/lib/tmpfiles.d/homebrew.conf`

Der entscheidende Fix aus atomic-brew: existiert `/var/home/linuxbrew`
bereits User-owned, überspringt der Homebrew-Installer die sudo-Phase.
`/var`-Verzeichnisse werden auf Atomic deklarativ angelegt, nicht im
Containerfile.

```bash
cat > overlay/usr/lib/tmpfiles.d/homebrew.conf << 'EOF'
#Typ Pfad                 Modus User Gruppe Alter
d    /var/home/linuxbrew    0755  1000 1000   -
EOF
```

> [!tip] UID/GID 1000 statt `fritz`
> Der erste angelegte Nutzer ist auf jedem Gerät 1000 — das Overlay bleibt
> geräteübergreifend identisch. `systemd-tmpfiles-setup` läuft früh beim
> Boot, der User-Dienst erst nach Login: das Verzeichnis ist immer schon da.

### `overlay/usr/lib/systemd/user/homebrew-bootstrap.service`

```bash
cat > overlay/usr/lib/systemd/user/homebrew-bootstrap.service << 'EOF'
[Unit]
Description=Homebrew Erstinstallation nach /var/home/linuxbrew
ConditionPathExists=!/var/home/linuxbrew/.linuxbrew/bin/brew

[Service]
Type=oneshot
ExecStart=/usr/libexec/noctarow/homebrew-bootstrap.sh

[Install]
WantedBy=default.target
EOF
```

> [!warning] Kein `network-online.target` in der User-Session
> User-Units können nicht sauber auf das System-Netzwerkziel warten.
> Fehlt beim ersten Login das Netz, scheitert die Unit — und läuft beim
> nächsten Login erneut, weil `ConditionPathExists=!` auf das brew-Binary
> prüft. Bewusst so belassen: selbstheilend.

### `overlay/usr/libexec/noctarow/homebrew-bootstrap.sh`

Läuft als **User** (brew verlangt das). Installiert brew, verankert die
PATHs für **beide** Shells und zieht nushell/helix plus Leaf-Tools:

```bash
cat > overlay/usr/libexec/noctarow/homebrew-bootstrap.sh << 'EOF'
#!/usr/bin/bash
set -euo pipefail

BREW=/var/home/linuxbrew/.linuxbrew/bin/brew
[ -x "$BREW" ] && exit 0

export NONINTERACTIVE=1
curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh | bash

# bash-Seite verankern (idempotent)
if ! grep -q 'linuxbrew.*shellenv' "$HOME/.bashrc" 2>/dev/null; then
    echo 'eval "$(/var/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> "$HOME/.bashrc"
fi

# Userland: nushell und helix kommen AUSSCHLIESSLICH hierueber, nie per dnf
"$BREW" install nushell helix jq ripgrep

# nushell-Seite verankern: env.nu, marker-guarded (nushell liest kein profile.d)
NU_ENV="$HOME/.config/nushell/env.nu"
mkdir -p "$(dirname "$NU_ENV")"
if ! grep -q 'NOCTAROW-BREW' "$NU_ENV" 2>/dev/null; then
    cat >> "$NU_ENV" << 'NUEOF'
# >>> NOCTAROW-BREW >>>
$env.PATH = ($env.PATH | prepend [
    "/var/home/linuxbrew/.linuxbrew/bin"
    "/var/home/linuxbrew/.linuxbrew/sbin"
])
$env.HOMEBREW_PREFIX = "/var/home/linuxbrew/.linuxbrew"
$env.HOMEBREW_CELLAR = "/var/home/linuxbrew/.linuxbrew/Cellar"
$env.HOMEBREW_REPOSITORY = "/var/home/linuxbrew/.linuxbrew/Homebrew"
# <<< NOCTAROW-BREW <<<
NUEOF
fi
EOF
```

> [!note] User-Config statt Image-Drop-in — hier die richtige Ausnahme
> Das Prinzip „system-weite Drop-ins vor User-Configs" gilt für Dinge im
> Image. Die brew-nushell liegt aber selbst in `/var` und ihr Vendor-
> Autoload-Pfad ist beim brew-Build einkompiliert und nicht `/usr/share` —
> ein Image-Drop-in griffe ins Leere. Der Bootstrap schreibt deshalb
> marker-guarded in die User-`env.nu`, im selben Lebenszyklus wie brew.

### `overlay/usr/libexec/noctarow/terminal-shell` — der Wrapper

nushell wird dem Terminal zugeordnet, nicht dem Login. Damit foot auch im
Fenster zwischen erstem Login und abgeschlossenem Bootstrap (oder ohne
Netz) startfähig bleibt, zeigt `foot.ini` auf einen Wrapper:

```bash
cat > overlay/usr/libexec/noctarow/terminal-shell << 'EOF'
#!/usr/bin/bash
# Terminal-Shell-Zuordnung: nushell aus brew, Fallback bash.
NU=/var/home/linuxbrew/.linuxbrew/bin/nu
if [ -x "$NU" ]; then
    exec "$NU" "$@"
fi
exec /usr/bin/bash "$@"
EOF
```

### `overlay/etc/xdg/foot/foot.ini`

```bash
cat > overlay/etc/xdg/foot/foot.ini << 'EOF'
[main]
shell=/usr/libexec/noctarow/terminal-shell
font=monospace:size=12
EOF
```

Login-Shell bleibt unangetastet bash — kein `chsh`, kein
`/etc/passwd`-Risiko bei Image-Wechseln.

### Sway-Drop-ins und Environment

Unverändert aus dem Bestand übernehmen (`30-borders.conf`,
`50-keyboard.conf`, `70-output.conf` mit eDP-1 `scale 1.5`, leere
`90-bar.conf`/`90-swayidle.conf`, `95-noctalia.conf` mit
`exec qs -c noctalia-shell`) — jetzt unter
`overlay/usr/share/sway/config.d/`.

```bash
printf 'exec qs -c noctalia-shell\n' > overlay/usr/share/sway/config.d/95-noctalia.conf
: > overlay/usr/share/sway/config.d/90-bar.conf
: > overlay/usr/share/sway/config.d/90-swayidle.conf
```

> [!check] Dokumentations-Drift hiermit aufgelöst: `/etc/sway/environment`
> Die Noctalia-Sitzung hat verifiziert: `/usr/share/sway/environment`
> **existiert auf Fedora nicht**; `/usr/bin/start-sway` sourct
> `/etc/sway/environment`. Das `COPY … /usr/share/sway/environment` aus
> [[docs/09-yoga-buildumgebung]] ist obsolet. Neuer Weg: die Datei liegt
> als `environment.noctarow` unter `/usr/share/noctarow/` und wird im
> Build **angehängt** — der Fedora-Bestand bleibt erhalten.
> `09-yoga-buildumgebung` entsprechend korrigieren.

## `Containerfile`

```dockerfile
FROM quay.io/fedora-ostree-desktops/sway-atomic:44

# Manche Pakete verlangen ein vorhandenes /var/roothome, sonst bricht der Build ab.
RUN mkdir -p /var/roothome

# Terra (Fyra Labs): Quelle für noctalia-shell/noctalia-qs, x86_64 + aarch64.
# Gevendort inkl. excludepkgs=terra-obsolete und skip_if_unavailable=False.
COPY terra.repo /etc/yum.repos.d/terra.repo

# --- Schicht 1: Noctalia (dnf) ---
# noctalia-qs verlangt Qt 6.11; dnf hebt qt6-qtbase als normale Abhängigkeit an.
# Bewusst NICHT im Image: nushell und helix — die kommen per brew nach /var.
RUN dnf install -y noctalia-shell \
    && dnf clean all \
    && rm -rf /var/cache/libdnf5 /var/cache/dnf

# Guard: erfolgreicher dnf-Exit-Code ist KEIN Beweis der Installation
# (Obsoletes-Umleitung, siehe terra-obsolete-Vorfall).
RUN rpm -q noctalia-shell

# --- Schicht 2: Build-Toolchain für Homebrew (read-only in /usr) ---
# brew selbst landet zur Laufzeit in /var/home/linuxbrew, nie im Image.
RUN dnf -y install \
        @development-tools \
        gcc gcc-c++ make \
        procps-ng curl file git \
        libxcrypt-compat \
    && dnf clean all \
    && rm -rf /var/cache/libdnf5 /var/cache/dnf

# --- Schicht 3: Overlay (Sway, foot, SDDM, tmpfiles, Bootstrap, Wrapper) ---
COPY overlay/ /

RUN chmod +x /usr/libexec/noctarow/homebrew-bootstrap.sh \
             /usr/libexec/noctarow/terminal-shell \
    && systemctl --global enable homebrew-bootstrap.service

# Sway-Umgebung: append, nicht ersetzen — start-sway sourct /etc/sway/environment.
RUN cat /usr/share/noctarow/environment.noctarow >> /etc/sway/environment

# Qualitätssicherung
RUN bootc container lint

LABEL org.opencontainers.image.title="Noctarow" \
      org.opencontainers.image.description="Fedora Sway Atomic + Noctalia + Homebrew-Toolchain (nushell/helix via brew)" \
      org.opencontainers.image.vendor="MetaRow Software UG" \
      containers.bootc="1"
```

> [!note] Layer-Reihenfolge ist Cache-Strategie
> Noctalia ändert sich am häufigsten; die Toolchain-Schicht ist die
> stabilste und teuerste. Bei Config-Iterationen (nur Overlay) bleibt der
> gesamte dnf-Cache stehen.

## Bauen und aktivieren (Yoga, bash)

```bash
cd ~/projekte/noctarow

# sudo zwingend: Image muss in root's containers-storage für bootc switch
sudo podman build -t quay.io/metarow/noctarow:44-amd64 -t localhost/noctarow:44 .

# Guard von außen wiederholen — kostet Sekunden, spart einen Boot-Zyklus
sudo podman run --rm localhost/noctarow:44 rpm -q noctalia-shell
sudo podman run --rm localhost/noctarow:44 bash -c \
    'test -x /usr/libexec/noctarow/homebrew-bootstrap.sh && test -x /usr/libexec/noctarow/terminal-shell && echo overlay-ok'
```

Aktivieren und Rückweg:

```bash
sudo bootc switch --transport containers-storage localhost/noctarow:44
sudo systemctl reboot

# Rückweg
sudo bootc rollback
sudo systemctl reboot
```

> [!info] `/var` überlebt Rollback und Image-Wechsel
> `/var/home/linuxbrew` bleibt bei jedem Wechsel erhalten — Rückschalten
> entfernt brew, nushell und helix **nicht**. Sauberes Entfernen bei
> Bedarf:
> ```bash
> sudo rm -rf /var/home/linuxbrew
> ```

## Erstlogin-Kontrolle (nach Switch, bash)

```bash
# tmpfiles hat vorbereitet?
ls -ld /var/home/linuxbrew

# Bootstrap gelaufen?
systemctl --user status homebrew-bootstrap.service
test -x /var/home/linuxbrew/.linuxbrew/bin/brew && echo brew-ok

# Werkzeuge da, und zwar aus brew?
/var/home/linuxbrew/.linuxbrew/bin/nu --version
/var/home/linuxbrew/.linuxbrew/bin/hx --version
command -v nu hx        # nach neuem bash-Login: brew-Pfade

# Terminal-Zuordnung: neues foot-Fenster öffnen -> landet in nushell.
# Kontrolle dort: `version` und `$env.PATH | where $it =~ linuxbrew`

# Login-Shell unangetastet?
getent passwd "$USER" | cut -d: -f7    # -> /bin/bash
```

## Offene Punkte

- [ ] `brew install --dry-run nushell helix` auf x86_64: Bottles vorhanden
      oder Quelltext-Bau? (Auf aarch64 laut 13 noch offen — hier für das
      Yoga separat prüfen)
- [ ] Erstlogin-Fenster live testen: foot **vor** abgeschlossenem
      Bootstrap öffnen → Wrapper muss sauber in bash landen
- [ ] `90-bar.conf`-Dateinamen gegen aktuelle `sway-config-fedora`
      verifizieren (waybar-exec-Snippet)
- [ ] Toolchain-Größe messen (`@development-tools` ist schwer) — Kandidat
      fürs Abspecken, falls die 15-GB-`/var`-Grenze auf dem Yoga drückt
- [ ] `09-yoga-buildumgebung` nachziehen: nushell/helix aus dem
      Containerfile streichen, `environment`-Drift, Overlay-Struktur,
      bash-Befehle in der Buildumgebung
- [ ] Rollen-Matrix bestätigen: `10-core` (Toolchain + Bootstrap inkl.
      nushell/helix) in allen Rollen — deckt sich wieder mit dem
      atomic-brew-Original
- [ ] Hyprland-Rolle: separates Modul evaluieren (COPR-Quelle, kein
      offizielles Atomic-Image) — nicht Teil der Basis
