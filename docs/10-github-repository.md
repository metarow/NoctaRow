---
titel: Öffentliches GitHub-Repository
teil_von: "[[README]]"
tags: [github, ci, actions, multi-arch, quay, ssh, lizenz]
---

# 10 — Öffentliches GitHub-Repository

Ziel: `github.com/metarow/noctarow` öffentlich, mit CI, die bei jedem Push
beide Architekturen baut und nach `quay.io/metarow/noctarow` schiebt.

Der Gewinn ist nicht Öffentlichkeit als Selbstzweck. Es ist:

- **Ein `git pull` statt Tarball-Herumtragen** zwischen XPS, Yoga und
  CachyOS-Desktop.
- **Kostenlose arm64-Runner.** GitHub stellt sie für öffentliche Repositories
  bereit. Damit entfällt die Notwendigkeit, auf dem XPS von Hand zu bauen.
- **Reproduzierbare Builds** ohne Zustand aus deiner Werkstatt.

## Schritt 1 — Repository anlegen

> [!warning] Zugangsdaten
> Das folgende erledigst du selbst — in der Weboberfläche oder mit `gh auth
> login`. Tokens, SSH-Schlüssel und Robot-Credentials gehören nirgends in
> dieses Repository und in kein Skript.

Auf dem Yoga ist `gh` bereits gelayert (siehe
[[docs/09-yoga-buildumgebung#Schritt 2]]):

```nu
gh auth login
```

Dann, im lokalen Projektverzeichnis:

```nu
cd ~/projekte/noctarow
gh repo create metarow/noctarow --public --source . --remote origin --push
```

Alternativ von Hand auf `github.com/organizations/metarow`, dann:

```nu
git remote add origin git@github.com:metarow/noctarow.git
git branch -M main
git push -u origin main
```

### SSH statt HTTPS

```nu
ssh-keygen -t ed25519 -C "fritz@metarow"
cat ~/.ssh/id_ed25519.pub
```

Den öffentlichen Schlüssel unter *GitHub → Settings → SSH and GPG keys*
eintragen. **Nur den öffentlichen.** Der private verlässt das Gerät nie.

```nu
ssh -T git@github.com
```

## Schritt 2 — Lizenz und Metadaten

Ohne Lizenz ist ein öffentliches Repository rechtlich unbrauchbar — niemand
darf es nutzen, auch wenn es öffentlich sichtbar ist.

```nu
r#'MIT License

Copyright (c) 2026 MetaRow Software UG

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
'# | save --force LICENSE
```

> [!note] Fremde Lizenzen
> Noctalia wird per `git clone` ins Image gezogen und behält seine eigene
> Lizenz. Dein `LICENSE` deckt **deine** Konfiguration und Skripte ab, nicht
> die eingebetteten Komponenten. Ein Satz dazu im README ist ehrlicher als das
> Weglassen.

## Schritt 3 — Secrets für die CI

Unter *Repository → Settings → Secrets and variables → Actions*:

| Name | Wert |
|---|---|
| `QUAY_USERNAME` | `metarow+noctarow_push` (Robot aus [[docs/04-quay-veroeffentlichung]]) |
| `QUAY_TOKEN` | das generierte Robot-Token |

**Nicht dein persönliches Quay-Passwort.** Der Robot hat nur Schreibrecht auf
genau dieses eine Repository.

## Schritt 4 — Workflow anlegen

```nu
mkdir .github/workflows
```

```nu
r#'name: build

on:
  push:
    branches: [main]
    paths-ignore: ["docs/**", "*.md"]
  pull_request:
  schedule:
    # woechentlich neu bauen, damit Fedora-Updates einfliessen
    - cron: "0 4 * * 1"
  workflow_dispatch:

env:
  IMAGE: quay.io/metarow/noctarow
  FEDORA_MAJOR: "44"

jobs:
  build:
    strategy:
      fail-fast: false
      matrix:
        include:
          - runner: ubuntu-24.04
            arch: amd64
          - runner: ubuntu-24.04-arm
            arch: arm64
    runs-on: ${{ matrix.runner }}
    steps:
      - uses: actions/checkout@v4

      - name: Platz schaffen
        run: |
          sudo rm -rf /usr/share/dotnet /opt/ghc /usr/local/share/boost
          df -h /

      - name: Bauen
        run: |
          podman build \
            --build-arg FEDORA_MAJOR=${{ env.FEDORA_MAJOR }} \
            --tag ${{ env.IMAGE }}:${{ env.FEDORA_MAJOR }}-${{ matrix.arch }} \
            .

      - name: Anmelden
        if: github.event_name != 'pull_request'
        run: |
          podman login quay.io \
            -u "${{ secrets.QUAY_USERNAME }}" \
            -p "${{ secrets.QUAY_TOKEN }}"

      - name: Pushen
        if: github.event_name != 'pull_request'
        run: |
          podman push ${{ env.IMAGE }}:${{ env.FEDORA_MAJOR }}-${{ matrix.arch }}

  manifest:
    needs: build
    if: github.event_name != 'pull_request'
    runs-on: ubuntu-24.04
    steps:
      - name: Anmelden
        run: |
          podman login quay.io \
            -u "${{ secrets.QUAY_USERNAME }}" \
            -p "${{ secrets.QUAY_TOKEN }}"

      - name: Manifest-List bauen und pushen
        run: |
          DATUM=$(date +%Y%m%d)
          LIST=${{ env.IMAGE }}:${{ env.FEDORA_MAJOR }}

          podman manifest create $LIST
          podman manifest add $LIST docker://${{ env.IMAGE }}:${{ env.FEDORA_MAJOR }}-amd64
          podman manifest add $LIST docker://${{ env.IMAGE }}:${{ env.FEDORA_MAJOR }}-arm64

          podman manifest push --all $LIST docker://$LIST
          podman manifest push --all $LIST docker://${{ env.IMAGE }}:${{ env.FEDORA_MAJOR }}.$DATUM

      - name: Ergebnis
        run: |
          skopeo inspect --raw docker://${{ env.IMAGE }}:${{ env.FEDORA_MAJOR }} \
            | jq ".manifests[].platform"
'# | save --force .github/workflows/build.yml
```

> [!important] `stable` wird nicht automatisch verschoben
> Die CI baut und pusht `44` und `44.<datum>`. Der Tag `stable`, auf den die
> Schulungsflotte zeigt, bleibt unangetastet. Ihn verschiebst du **von Hand**,
> nachdem du den Stand auf dem Yoga geprüft hast:
>
> ```nu
> skopeo copy docker://quay.io/metarow/noctarow:44.20260710 docker://quay.io/metarow/noctarow:stable
> ```
>
> Eine CI, die `stable` bewegt, ist eine CI, die deinen Kurs unterbricht.

## Schritt 5 — Was `ubuntu-24.04-arm` bedeutet

Der arm64-Runner ist ein **nativer** ARM-Host, keine Emulation. Damit baut die
CI dein aarch64-Image in derselben Zeit wie das amd64. Die Notwendigkeit,
auf dem XPS von Hand zu bauen, entfällt.

> [!warning] Nur für öffentliche Repositories kostenlos
> Wird das Repository privat, kostet der arm64-Runner Minuten aus dem
> Actions-Kontingent. Das ist ein Argument dafür, das Image-Repo öffentlich zu
> halten und Kursinhalte getrennt zu verwalten.

## Schritt 6 — Platzproblem auf den Runnern

GitHub-Runner haben ~14 GB frei. Ein Fedora-Desktop-Image mit Qt6 kommt dem
nahe. Der `Platz schaffen`-Schritt oben räumt vorab auf. Wenn es trotzdem eng
wird:

```yaml
      - uses: jlumbroso/free-disk-space@main
        with:
          tool-cache: true
```

## Schritt 7 — Der neue Arbeitsablauf

Ab jetzt trägst du keine Dateien mehr herum.

```nu
# Auf dem Yoga: aendern, testen, pushen
hx sway/50-keyboard.conf
noctarow build
noctarow test-nested
git commit -am "Tastatur: repeat_rate erhoeht"
git push

# CI baut beide Architekturen und die Manifest-List.
# Auf jeder Fleet-Maschine dann:
sudo bootc upgrade
systemctl reboot
```

Und auf dem XPS oder dem CachyOS-Desktop:

```nu
git pull
```

## Was nicht ins Repository gehört

`.gitignore` deckt bereits ab:

```
output/
*.vhdx
*.qcow2
*.raw
cosign.key
*.pem
auth.json
.env
```

Ergänze bei Bedarf `hosts/*/geheim*`. Und prüfe vor dem ersten `git push`:

```nu
git log -p | grep -i -E 'token|password|secret|BEGIN.*PRIVATE' | head
```

Ein einmal gepushtes Secret ist öffentlich, auch nach dem Löschen des Commits.
Dann hilft nur: Token bei Quay widerrufen, neu erzeugen.
