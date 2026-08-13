---
title: "Leitfaden: Eigenes bootc-Image mit Homebrew-Toolchain (atomic-brew)"
date: 2026-07-22
tags:
  - linux
  - fedora-atomic
  - bootc
  - homebrew
  - coaching
  - bash
aliases:
  - "atomic-brew Image bauen"
  - "Homebrew-Image bauen"
  - "Coaching bootc Leitfaden"
status: aktiv
---

# Eigenes bootc-Image mit Homebrew-Toolchain — `atomic-brew`

Kompletter Durchlauf vom leeren Verzeichnis bis zum aktivierten, getesteten und wieder zurückgerollten Image. Zielsystem ist [[Fedora Sway Atomic]], die Build-Toolchain wandert ins Image, [[Homebrew]] selbst zur Laufzeit nach `/var/home/linuxbrew`.

> [!abstract] Grundprinzip
> **Ins Image (`/usr`, read-only):** Compiler, `make`, Basis-Werkzeuge – alles, was Homebrew zum Bauen braucht.
> **Zur Laufzeit (`/var/home/linuxbrew`):** Homebrew selbst inkl. Cellar & Sources, sowie die eigentlichen Nutzer-Werkzeuge **Nushell** und **Helix**, die per `brew` installiert werden. Grund: `brew` läuft nicht als root, und Inhalte unter `/var` werden im Image-Build ohnehin nicht zuverlässig ins OSTree-Commit übernommen.

> [!important] Login-Shell ist bash
> Dieser Leitfaden setzt **bash als Login-Shell** voraus. Alle Konsolenbefehle bis zur Aktivierung sind daher bash. Nushell und Helix installiert der First-Boot-Bootstrap über `brew` – **Nushell-Befehle tauchen erst wieder in [[#8. Testen]] auf, also erst, wenn das Image `atomic-brew` aktiv ist.**

---

## 0. Voraussetzungen

Auf dem **Build-Rechner** – hier ebenfalls **Fedora Sway Atomic** – reicht die schlanke Basis:

- `podman` (rootless genügt zum Bauen und Pushen)
- `git`
- Ein GitHub-Account mit aktiviertem **GitHub Container Registry (GHCR)**

`just` und `cosign` liegen auf einem Atomic-System nicht vor und werden **nicht** ins Basissystem gelayert. Je nach Werkzeug-Typ zwei leichtgewichtige Wege:

**`just` → statische Binary nach `~/.local/bin`** (persistent, weil bei jedem lokalen Build gebraucht; ein Orchestrator muss auf dem Host laufen, nicht im Container):

```bash
mkdir -p ~/.local/bin
curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh \
  | bash -s -- --to ~/.local/bin
just --version
```

Fedora nimmt `~/.local/bin` in der Standard-`.bash_profile` in den PATH auf – nach einem neuen Login ist `just` verfügbar. Der Installer zieht eine vorkompilierte, statisch gelinkte Binary; nichts wird gebaut oder gelayert.

**`cosign` → per Container** (self-contained, lokal nur einmalig zum Schlüssel-Erzeugen gebraucht – das Signieren übernimmt die CI über `sigstore/cosign-installer`):

```bash
podman run --rm -it -v "$PWD":/work:Z -w /work \
  gcr.io/projectsigstore/cosign generate-key-pair
```

`-it` ist wichtig, damit die Passwort-Abfrage funktioniert; `:Z` relabelt das Volume für SELinux. Optional als Wrapper-Funktion in die `.bashrc`, dann verhält sich cosign wie lokal installiert:

```bash
cosign() {
  podman run --rm -it -v "$PWD":/work:Z -w /work \
    gcr.io/projectsigstore/cosign "$@"
}
```

> [!note] Warum nicht beides gleich behandeln
> `cosign` ist eine in sich geschlossene CLI → containerbar. `just` orchestriert lokale `podman build`-Aufrufe → im Container müsste es Podman-in-Podman ansprechen und bräche genau seine Aufgabe. Wer es dennoch einheitlich will: `cosign` gibt es als `cosign-linux-amd64` ebenfalls auf den GitHub-Releases, dann nach `~/.local/bin` legen und `chmod +x`.

Auf dem **Zielsystem** (Coaching-Rechner) ist bereits Fedora Sway Atomic (F41+) installiert, damit `bootc` verfügbar ist.

---

## 1. Projektverzeichnis anlegen

```bash
mkdir atomic-brew && cd atomic-brew
```

Wir bauen folgende Struktur auf:

```
atomic-brew/
├── Containerfile
├── README.md
├── .gitignore
├── Justfile
├── overlay/
│   └── usr/
│       ├── lib/
│       │   ├── tmpfiles.d/
│       │   │   └── homebrew.conf
│       │   └── systemd/
│       │       └── user/
│       │           └── homebrew-bootstrap.service
│       └── libexec/
│           └── atomic-brew/
│               └── bootstrap.sh
└── .github/
    └── workflows/
        └── build.yml
```

```bash
mkdir -p overlay/usr/lib/tmpfiles.d
mkdir -p overlay/usr/lib/systemd/user
mkdir -p overlay/usr/libexec/atomic-brew
mkdir -p .github/workflows
```

---

## 2. Git initialisieren

```bash
git init
git branch -m main
```

`.gitignore` – wir versionieren nur die Quellen, keine gebauten Artefakte:

```gitignore
# .gitignore
*.tar
*.qcow2
*.iso
.build/
image-out/
cosign.key
```

> [!warning] Signierschlüssel niemals committen
> `cosign.key` (privater Schlüssel) gehört in die GitHub-Secrets, nicht ins Repo. Deshalb steht er in der `.gitignore`.

---

## 3. Alle Dateien anlegen

### 3.1 `Containerfile`

Das Herzstück. Es zieht das Basisimage, legt die **Toolchain** in `/usr` ab und bringt das Overlay (tmpfiles-Regel, Bootstrap-Skript, systemd-User-Unit) mit. Bewusst **nicht** im Image: `nushell` und `helix` – die kommen später über `brew`.

```dockerfile
# Containerfile
FROM quay.io/fedora-ostree-desktops/sway-atomic:44

# Manche Pakete verlangen ein vorhandenes /var/roothome, sonst bricht der Build ab.
RUN mkdir -p /var/roothome

# --- Build-Toolchain für Homebrew (bleibt read-only im Image) ---
RUN dnf -y install \
        @development-tools \
        gcc gcc-c++ make \
        procps-ng curl file git \
        libxcrypt-compat && \
    dnf clean all

# --- Overlay: tmpfiles-Regel, Bootstrap-Skript, systemd-User-Unit ---
COPY overlay/ /

# --- Bootstrap ausführbar machen und für alle User aktivieren ---
RUN chmod +x /usr/libexec/atomic-brew/bootstrap.sh && \
    systemctl --global enable homebrew-bootstrap.service

# --- bootc-Lint als Qualitätssicherung im Build ---
RUN bootc container lint

LABEL org.opencontainers.image.title="Atomic Brew" \
      org.opencontainers.image.description="Fedora Sway Atomic + Homebrew-Toolchain (nushell/helix via brew)" \
      containers.bootc="1"
```

> [!note] Warum `nushell` und `helix` nicht ins Image?
> Sie sind die Nutzer-Werkzeuge, nicht Teil der Basis. Über `brew` bleiben sie unabhängig vom Image-Lebenszyklus aktualisierbar und liegen im beschreibbaren `/var`. Im Image steht nur die **Toolchain**, die Homebrew zum Bauen braucht.

### 3.2 `overlay/usr/lib/tmpfiles.d/homebrew.conf`

**Der entscheidende Fix.** Homebrew will seinen Default-Prefix unter `/home/linuxbrew/.linuxbrew` (= `/var/home/linuxbrew/.linuxbrew`) anlegen. Existiert das übergeordnete Verzeichnis noch nicht, braucht der Installer `sudo` zum Anlegen – was ein `systemctl --user`-Dienst nicht hat. Deshalb erzeugen wir `/var/home/linuxbrew` **vorab und im Besitz des Users**; dann überspringt der Installer die sudo-Phase komplett.

Auf Atomic legt man `/var`-Verzeichnisse nicht im Containerfile an, sondern deklarativ über `systemd-tmpfiles`:

```
# /usr/lib/tmpfiles.d/homebrew.conf
#Typ Pfad                Modus User Gruppe Alter
d    /var/home/linuxbrew  0755  1000 1000   -
```

> [!tip] Warum UID/GID `1000` statt `fritz`
> Der erste angelegte Nutzer ist auf jedem Gerät UID 1000 – so bleibt das Overlay geräteübergreifend identisch. Auf einer konkreten Maschine kannst du stattdessen `fritz fritz` schreiben. `systemd-tmpfiles-setup` läuft früh beim Boot (System-Ebene), der User-Dienst erst nach dem Login – das Verzeichnis ist also immer schon da.

### 3.3 `overlay/usr/libexec/atomic-brew/bootstrap.sh`

Installiert Homebrew, verankert es in der `.bashrc` und installiert darüber Nushell und Helix. Läuft als **User** (nicht root), was `brew` verlangt.

```bash
#!/usr/bin/env bash
# /usr/libexec/atomic-brew/bootstrap.sh
set -euo pipefail

MARKER="$HOME/.config/atomic-brew/bootstrapped"
BREW="/var/home/linuxbrew/.linuxbrew/bin/brew"

# 1. Homebrew installieren (Zielverzeichnis existiert dank tmpfiles bereits,
#    gehört dem User -> Installer läuft ohne sudo durch)
if [ ! -x "$BREW" ]; then
    NONINTERACTIVE=1 /usr/bin/bash -c \
      "curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh | bash"
fi

# 2. brew shellenv dauerhaft in die .bashrc eintragen -> passt den PATH an
LINE="eval \"\$(${BREW} shellenv)\""
if ! grep -qF "$LINE" "$HOME/.bashrc" 2>/dev/null; then
    printf '\n# Homebrew\n%s\n' "$LINE" >> "$HOME/.bashrc"
fi

# 3. Nushell und Helix für den Nutzer über brew installieren
eval "$("$BREW" shellenv)"
brew install nushell helix

# 4. Abschluss markieren, damit der Dienst nicht erneut komplett durchläuft
mkdir -p "$(dirname "$MARKER")"
touch "$MARKER"
```

> [!info] So passt Brew den `$PATH` über die `.bashrc` an
> Zeile 2 schreibt `eval "$(/var/home/linuxbrew/.linuxbrew/bin/brew shellenv)"` in die `.bashrc`. Das ist der offizielle Homebrew-Weg: `brew shellenv` setzt `HOMEBREW_PREFIX`, `PATH`, `MANPATH` usw. bei jedem Öffnen einer Shell. Fedoras `.bash_profile` sourct die `.bashrc` bereits, sodass sowohl Login- als auch interaktive Shells den Pfad bekommen.

### 3.4 `overlay/usr/lib/systemd/user/homebrew-bootstrap.service`

```ini
# /usr/lib/systemd/user/homebrew-bootstrap.service
[Unit]
Description=Homebrew + Nushell/Helix Erstinstallation nach /var/home/linuxbrew
ConditionPathExists=!%h/.config/atomic-brew/bootstrapped
After=default.target

[Service]
Type=oneshot
ExecStart=/usr/libexec/atomic-brew/bootstrap.sh
RemainAfterExit=yes

[Install]
WantedBy=default.target
```

> [!info] Der `/home` → `/var/home`-Trick
> Homebrews Linux-Default `/home/linuxbrew/.linuxbrew` landet auf Atomic über den Symlink `/home` → `/var/home` automatisch in `/var/home/linuxbrew/.linuxbrew`. Der Marker unter `~/.config/atomic-brew/bootstrapped` sorgt dafür, dass der Bootstrap nur einmal komplett läuft; scheitert er (z. B. kein Netz), versucht er es beim nächsten Login erneut.

### 3.5 `Justfile` (optional, spart Tipparbeit)

```make
# Justfile
image := "ghcr.io/DEIN-GH-NAME/atomic-brew"
tag   := "latest"

build:
    podman build -t {{image}}:{{tag}} .

push:
    podman push {{image}}:{{tag}}

lint:
    podman run --rm {{image}}:{{tag}} bootc container lint

login:
    podman login ghcr.io
```

### 3.6 `README.md`

```markdown
# Atomic Brew

Fedora Sway Atomic + Homebrew-Toolchain als bootc-Image.

- Build-Toolchain im Image (`/usr`)
- Homebrew zur Laufzeit in `/var/home/linuxbrew`
- Login-Shell: bash; `brew shellenv` wird in die `.bashrc` eingetragen
- Nushell und Helix werden per `brew` installiert (nicht im Image)

## Aktivieren
    sudo bootc switch ghcr.io/DEIN-GH-NAME/atomic-brew:latest
    sudo systemctl reboot

## Zurückrollen
    sudo bootc rollback
    sudo systemctl reboot
```

### 3.7 `.github/workflows/build.yml`

Baut das Image bei jedem Push, lädt es nach GHCR und signiert es mit cosign.

```yaml
# .github/workflows/build.yml
name: build-image

on:
  push:
    branches: [main]
  schedule:
    - cron: "0 4 * * 1"   # wöchentlich, damit Basis-Updates einfließen
  workflow_dispatch:

env:
  IMAGE: ghcr.io/${{ github.repository_owner }}/atomic-brew

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4

      - name: Build
        run: podman build -t "${IMAGE}:latest" .

      - name: Login GHCR
        run: echo "${{ secrets.GITHUB_TOKEN }}" | podman login ghcr.io -u "${{ github.actor }}" --password-stdin

      - name: Push
        id: push
        run: |
          podman push "${IMAGE}:latest" --digestfile=/tmp/digest
          echo "digest=$(cat /tmp/digest)" >> "$GITHUB_OUTPUT"

      - name: Cosign install
        uses: sigstore/cosign-installer@v3

      - name: Sign
        env:
          COSIGN_PRIVATE_KEY: ${{ secrets.COSIGN_PRIVATE_KEY }}
          COSIGN_PASSWORD: ${{ secrets.COSIGN_PASSWORD }}
        run: cosign sign --yes --key env://COSIGN_PRIVATE_KEY "${IMAGE}@${{ steps.push.outputs.digest }}"
```

Cosign-Schlüsselpaar einmalig erzeugen und den privaten Teil als Secret hinterlegen:

```bash
cosign generate-key-pair
# erzeugt cosign.key (privat -> Secret COSIGN_PRIVATE_KEY) und cosign.pub (öffentlich -> ins Repo)
```

---

## 4. Auswahl eines Basisimages

| Basisimage | Einsatz |
|---|---|
| `quay.io/fedora-ostree-desktops/sway-atomic:44` | **Empfohlen.** Deine Sway-Basis, bereits mit `dnf5` und `bootc`, cosign-signiert. Ideal, weil dein Setup darauf läuft. |
| `quay.io/fedora/fedora-bootc:44` | Minimaler bootc-Unterbau ohne Desktop – nur wenn du den Sway-Stack komplett selbst zusammenstellst. |

> [!note] Version festnageln
> Es lohnt sich, den Tag (`:44`) statt eines gleitenden `:latest` zu pinnen, damit Basisupdates kontrolliert einfließen. Der wöchentliche Cron im Workflow zieht die Basis-Updates dann bewusst nach.

Die unoffiziellen `fedora-ostree-desktops`-Images nutzen dieselben Pakete und Quellen wie die offiziellen Atomic-Desktops und sind inzwischen cosign-signiert.

---

## 5. Bilden des Images

Lokal auf dem Build-Rechner (bash):

```bash
# mit Just
just build
just lint

# oder direkt
podman build -t ghcr.io/DEIN-GH-NAME/atomic-brew:latest .
```

Der `RUN bootc container lint` im `Containerfile` prüft schon beim Build auf typische Fehler (falsche Pfade, kaputte Symlinks). Ein grüner Build heißt: das Image ist bootfähig aufgebaut.

Schnelltest des Dateisystems, ohne zu booten:

```bash
podman run --rm -it ghcr.io/DEIN-GH-NAME/atomic-brew:latest bash
# im Container:
which gcc make git
cat /usr/libexec/atomic-brew/bootstrap.sh
cat /usr/lib/tmpfiles.d/homebrew.conf
```

---

## 6. Hochladen der Dokumente und des Images auf GitHub

Hier laufen **zwei getrennte Ziele** zusammen: die Quellen/Doku ins Git-Repo auf `github.com`, das gebaute Image in die Registry `ghcr.io`.

### 6.1 Doku (Quelltexte) → github.com

```bash
git add .
git commit -m "Initiales bootc-Image atomic-brew mit Homebrew-Toolchain"

# Repo auf github.com anlegen, dann:
git remote add origin git@github.com:DEIN-GH-NAME/atomic-brew.git
git push -u origin main
```

Sobald der Workflow aus Abschnitt 3.7 durchläuft, baut GitHub das Image automatisch und pusht es. Für den **manuellen** Weg:

### 6.2 Image → ghcr.io

```bash
# Token mit Scope write:packages erzeugen (GitHub -> Settings -> Developer settings)
echo "$GH_TOKEN" | podman login ghcr.io -u DEIN-GH-NAME --password-stdin

just push
# oder
podman push ghcr.io/DEIN-GH-NAME/atomic-brew:latest
```

> [!warning] Paket-Sichtbarkeit auf „public" setzen
> Frisch gepushte GHCR-Pakete sind privat. Damit `bootc switch` das Image ohne Registry-Login ziehen kann, stellst du es unter **GitHub → Packages → Package settings → Change visibility → Public**. Für interne Nutzung alternativ die Zielgeräte per `podman login` authentifizieren.

---

## 7. Aktivieren des Images

Auf einem **Zielgerät** (bash). Zuerst den aktuellen Stand sichern, dann umschalten.

```bash
# aktuellen Zustand ansehen und die laufende Bereitstellung anheften (Schutz vor GC)
sudo bootc status
sudo ostree admin pin 0

# auf das eigene Image umschalten
sudo bootc switch ghcr.io/DEIN-GH-NAME/atomic-brew:latest
sudo systemctl reboot
```

`bootc switch` legt das neue Image als nächste Bootbereitstellung an; das bisherige System bleibt als **Rollback**-Eintrag erhalten.

> [!note] Signaturprüfung
> Fedoras Standard-Policy akzeptiert das Image direkt. Für verifizierte Signaturen hinterlegst du `cosign.pub` und eine Policy unter `/etc/containers/policy.json` bzw. `/etc/containers/registries.d/` – sinnvoll, sobald das Setup produktiv läuft.

---

## 8. Testen

Nach dem Reboot ist `atomic-brew` aktiv. **Ab hier stehen dir nach dem Bootstrap auch Nushell und Helix zur Verfügung.** Die folgenden Prüfbefehle laufen zunächst in bash:

```bash
# Läuft das eigene Image?
bootc status
# -> Booted image: ghcr.io/DEIN-GH-NAME/atomic-brew:latest

# Toolchain aus dem Image vorhanden?
which gcc; which make; which git; gcc --version

# Hat das tmpfiles-Overlay das Verzeichnis angelegt und dem User übergeben?
ls -ld /var/home/linuxbrew

# Bootstrap gelaufen? (User-Unit, ggf. ersten Login abwarten)
systemctl --user status homebrew-bootstrap.service
ls /var/home/linuxbrew/.linuxbrew/bin/brew

# Ist brew in der .bashrc verankert?
grep brew ~/.bashrc
```

Danach in einer **neuen** Login-Shell prüfen, ob der PATH über die `.bashrc` greift:

```bash
brew --version
echo "$PATH" | tr ':' '\n' | grep linuxbrew

# von brew installierte Nutzer-Werkzeuge
which nu hx
nu --version
```

Ist der Bootstrap noch nicht durch, einmal manuell anstoßen (bash):

```bash
systemctl --user start homebrew-bootstrap.service
```

> [!success] Erfolgskriterien
> `bootc status` zeigt dein Image · `gcc`/`make` liegen in `/usr` · `/var/home/linuxbrew` gehört dem User · `brew` liegt in `/var/home/linuxbrew` · `~/.bashrc` enthält die `brew shellenv`-Zeile · `nu` und `hx` sind über brew installiert.

### 8.1 Ab jetzt: Nushell verfügbar

Erst jetzt – mit aktivem `atomic-brew` und durchgelaufenem Bootstrap – existiert Nushell. Ein Aufruf von `nu` startet die Sitzung, in der dann native Nushell-Befehle funktionieren:

```nu
# in der Nushell-Sitzung
$env.PATH | where $it =~ linuxbrew
brew list
brew --version
```

Funktionstest von brew selbst (in bash oder nu identisch, da `brew` ein normales Binary ist):

```bash
brew install hello
hello
brew uninstall hello
```

---

## 9. Rückschalten auf das Ausgangsimage

Falls im Test etwas nicht passt – der transaktionale Kern von OSTree/bootc macht das gefahrlos (bash).

### 9.1 Schneller Rückweg (vorheriges Deployment)

```bash
sudo bootc rollback
sudo systemctl reboot
```

Das tauscht die aktuelle und die Rollback-Bereitstellung: Nach dem Reboot läuft wieder das Ausgangssystem, dein `atomic-brew`-Image bleibt als Rollback erhalten.

### 9.2 Vollständig zurück zum Stock-Image

Wenn du das eigene Image ganz verlassen willst:

```bash
sudo bootc switch quay.io/fedora-ostree-desktops/sway-atomic:44
sudo systemctl reboot
```

> [!info] `/var` bleibt erhalten
> `/var/home/linuxbrew` liegt in der beschreibbaren `/var`-Partition und übersteht sowohl Rollback als auch Image-Wechsel. Ein Rückschalten entfernt Homebrew, Nushell und Helix also **nicht**. Zum sauberen Entfernen bei Bedarf (bash):
> ```bash
> rm -rf /var/home/linuxbrew
> ```

---

## 10. Mehrere Image-Varianten für Geräterollen

Der Durchlauf oben baut **ein** Image (`atomic-brew`). Sobald mehrere Geräterollen ins Spiel kommen, die sich zu großen Teilen überschneiden, dupliziert man aber keine Containerfiles – man zerlegt jedes Feature in ein **Modul** und komponiert die Rollen daraus. Das ersetzt die einfache `Containerfile`/`Justfile` aus [[#3.1 `Containerfile`]] und [[#3.5 `Justfile` (optional, spart Tipparbeit)]], sobald du skalierst.

> [!abstract] Drei Feature-Klassen auf Atomic
> **Kernelmodul** → muss ins Image *und* ist kernel-gekoppelt (baut bei jedem Kernel-Update neu, ggf. Secure-Boot-Signatur). Teuer und heikel.
> **Paket** → Image-Layer, reihenfolge-unkritisch, billig.
> **Laufzeit/State** → gehört nach `/var`, gar nicht ins Image (Homebrew selbst, sowie Nushell und Helix per brew).

### 10.1 Rollen-Matrix

| Modul | Dozenten-PC (sway) | KI-Workstation (silverblue) | Entw. sway | Entw. silverblue |
|---|:---:|:---:|:---:|:---:|
| `10-core` (Brew-Toolchain, Bootstrap) | ✅ | ✅ | ✅ | ✅ |
| `15-noctalia` (Sway-Shell) | ✅ | – | ✅ | – |
| `20-voice-io` (Sprach-IO) | – | ✅ | – | ✅ |
| `30-displaylink` (**akmod**) | ✅ | – | – | – |
| `40-kvm-win11` | ✅ | ✅ | – | – |
| `50-nvidia` (**akmod**) | – | ✅ | – | – |
| **Basis** | `sway-atomic:44` | `silverblue:44` | `sway-atomic:44` | `silverblue:44` |

> [!note] Nushell/Helix in allen Rollen gleich
> `nu` und `hx` kommen in jeder Rolle identisch über den Brew-Bootstrap aus `10-core` – nicht über die Basis. Damit ist es egal, ob die Rolle auf Sway oder Silverblue steht.

### 10.2 Repo-Struktur

```
coaching-images/
├── Containerfile           # nimmt BASE_IMAGE + MODULES als ARG
├── modules/
│   ├── 10-core.sh          # Brew-Toolchain + Bootstrap aktivieren
│   ├── 15-noctalia.sh      # Sway-Shell Noctalia/Quickshell
│   ├── 20-voice-io.sh      # Sprach-IO (TTS/STT-Basis)
│   ├── 30-displaylink.sh   # evdi-akmod + DisplayLinkManager (proprietär)
│   ├── 40-kvm-win11.sh     # qemu/libvirt/ovmf/swtpm
│   └── 50-nvidia.sh        # akmod-nvidia
├── overlay/                # tmpfiles-Regel, bootstrap.sh, systemd-Unit (wie Abschnitt 3.2–3.4)
└── Justfile
```

### 10.3 Parametrisiertes `Containerfile`

```dockerfile
# Containerfile
ARG BASE_IMAGE=quay.io/fedora-ostree-desktops/sway-atomic:44
FROM ${BASE_IMAGE}
ARG MODULES="10-core.sh"

RUN mkdir -p /var/roothome
COPY modules/ /tmp/modules/
COPY overlay/  /
RUN set -euo pipefail; \
    chmod +x /usr/libexec/atomic-brew/bootstrap.sh; \
    for m in ${MODULES}; do echo "== $m =="; bash /tmp/modules/$m; done; \
    rm -rf /tmp/modules; \
    bootc container lint
```

### 10.4 Die vier Rollen im `Justfile`

```make
# Justfile
registry := "ghcr.io/DEIN-GH-NAME"
sway     := "quay.io/fedora-ostree-desktops/sway-atomic:44"
gnome    := "quay.io/fedora-ostree-desktops/silverblue:44"

_build base modules tag:
    podman build --build-arg BASE_IMAGE={{base}} \
                 --build-arg MODULES="{{modules}}" \
                 -t {{registry}}/coaching-{{tag}}:latest .

dozenten-pc:
    @just _build {{sway}}  "10-core.sh 15-noctalia.sh 30-displaylink.sh 40-kvm-win11.sh" dozenten-pc

ki-workstation:
    @just _build {{gnome}} "10-core.sh 20-voice-io.sh 40-kvm-win11.sh 50-nvidia.sh"      ki-workstation

dev-sway:
    @just _build {{sway}}  "10-core.sh 15-noctalia.sh"                                    dev-sway

dev-gnome:
    @just _build {{gnome}} "10-core.sh 20-voice-io.sh"                                    dev-gnome

build-all: dozenten-pc ki-workstation dev-sway dev-gnome
```

Jedes Feature steht damit genau einmal im Repo, jede Rolle ist eine deklarative Zeile. Push, `bootc switch`, Test und Rollback laufen pro Rolle exakt wie in den Abschnitten 6–9, nur mit dem jeweiligen Tag (`coaching-dozenten-pc:latest` usw.).

### 10.5 Die Module

Die unkritischen Paket-Module – sauber und vollständig. `10-core` installiert nur die Toolchain und aktiviert den Bootstrap; Nushell und Helix kommen anschließend per brew:

```bash
# modules/10-core.sh  — auf allen Rollen
#!/usr/bin/env bash
set -euo pipefail
dnf -y install @development-tools gcc gcc-c++ make procps-ng curl file git \
               libxcrypt-compat
dnf clean all
chmod +x /usr/libexec/atomic-brew/bootstrap.sh
systemctl --global enable homebrew-bootstrap.service
# tmpfiles-Regel, bootstrap.sh und die User-Unit kommen aus overlay/ (Abschnitt 3.2–3.4).
# nushell + helix installiert der Bootstrap zur Laufzeit über brew.
```

```bash
# modules/40-kvm-win11.sh  — Dozenten-PC, KI-Workstation
#!/usr/bin/env bash
set -euo pipefail
dnf -y install qemu-kvm libvirt virt-manager virt-install \
               edk2-ovmf swtpm swtpm-tools guestfs-tools
systemctl enable libvirtd.service
dnf clean all
# swtpm + edk2-ovmf sind der Win-11-Kern: UEFI + TPM 2.0. Ohne die beiden kein Win 11.
```

```bash
# modules/20-voice-io.sh  — KI-Workstation, Entw. silverblue
#!/usr/bin/env bash
set -euo pipefail
dnf -y install speech-dispatcher espeak-ng
dnf clean all
# STT/TTS-Engines (whisper.cpp, piper) laufen besser als Laufzeit über brew/pip/flatpak
# statt im Image — dann bleibt das Modul schlank und kernel-unabhängig.
```

Die drei heiklen Module – hier hängst du eigene Quellen ein; die Bezugsstellen musst du selbst prüfen und pinnen:

```bash
# modules/50-nvidia.sh  — KI-Workstation (KERNELMODUL)
#!/usr/bin/env bash
set -euo pipefail
F=$(rpm -E %fedora)
dnf -y install \
  "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${F}.noarch.rpm" \
  "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${F}.noarch.rpm"
dnf -y install akmod-nvidia xorg-x11-drv-nvidia-cuda
dnf clean all
```

> [!warning] NVIDIA ist der aufwändigste Layer
> `akmod-nvidia` baut gegen den exakten Kernel – im Image willst du das **vorgebaut**, nicht erst beim Boot. Bei aktiviertem Secure Boot muss das Modul mit deinem MOK signiert sein. Der robusteste Weg ist, das ublue-akmods-Muster (prebuilt + Signierung) zu übernehmen, statt die Pipeline selbst zusammenzusetzen.

```bash
# modules/30-displaylink.sh  — Dozenten-PC (KERNELMODUL + proprietär)
#!/usr/bin/env bash
set -euo pipefail
# evdi (akmod, kernelgebunden) + proprietärer DisplayLinkManager von Synaptics.
# Beides NICHT in den Fedora-Repos:
#   - evdi: über eine gepflegte COPR beziehen (Slug selbst prüfen/pinnen)
#   - DisplayLinkManager: RPM-URL von Synaptics als Build-Arg reinreichen
dnf -y install "${DISPLAYLINK_RPM_URL:?DISPLAYLINK_RPM_URL setzen}"
dnf clean all
```

> [!warning] DisplayLink ist proprietär
> Der `DisplayLinkManager` liegt nicht in den Fedora-Repos und ist lizenzrechtlich proprietär – ein solches Image gehört **nicht** in ein öffentliches GHCR-Paket. Für interne Nutzung das Paket privat halten und die Zielgeräte per `podman login` authentifizieren.

```bash
# modules/15-noctalia.sh  — Sway-Rollen
#!/usr/bin/env bash
set -euo pipefail
# Noctalia/Quickshell liegen nicht in den Fedora-Repos. Hier deine bereits bewährte
# Methode einhängen (COPR/Build) — die Config selbst kommt über overlay/.
```

### 10.6 Zwei Konsequenzen für deine Geräterollen

Nur **zwei** der vier Images tragen Kernelmodule: der Dozenten-PC (`evdi`) und die KI-Workstation (`nvidia`). Nur diese beiden bauen bei jedem Kernel-Update neu und brauchen ggf. MOK-Signatur. Die beiden Entwickler-Images sind reine Paket-Layer – schnell, robust und öffentlich teilbar. Der Wartungsaufwand konzentriert sich damit auf zwei klar benannte Images.

Und weil Homebrew samt Nushell und Helix Laufzeit ist (`/var/home/linuxbrew`), tragen alle vier nur die **Toolchain** im Image – die eigentliche Installation passiert überall gleich per First-Boot-Bootstrap. `10-core` und das `overlay/` sind über alle vier Rollen identisch.

> [!tip] Vor jedem neuen Modul: muss es überhaupt ins Image?
> Kann ein Feature Laufzeit sein (Flatpak, pip-venv, brew-Formel, First-Boot-Setup), schrumpft die Matrix weiter. Nur Kernelmodule (NVIDIA, DisplayLink) haben diese Wahl nicht – die müssen zwingend ins Image.

---

## Anhang: Der Lebenszyklus auf einen Blick

```
Quellen (github.com)  ──push──►  GitHub Actions  ──build+sign──►  Image (ghcr.io)
                                                                        │
                                                              bootc switch + reboot
                                                                        ▼
                                                                Zielgerät (aktiv)
                                                                        │
                                                     Test ok? ──ja──► produktiv
                                                          │
                                                         nein
                                                          ▼
                                              bootc rollback + reboot (Ausgangsimage)
```

## Verwandte Notizen

- [[Homebrew auf Fedora Atomic]]
- [[Bash Login-Shell und .bashrc]]
- [[bootc Grundlagen]]
- [[Coaching Fedora Sway Atomic]]
