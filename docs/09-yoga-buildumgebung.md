---
titel: Build-Umgebung auf dem Yoga (Fedora Sway Atomic)
teil_von: "[[README]]"
tags: [yoga920, atomic, rpm-ostree, podman, nushell, bootc, raw-strings, preflight, containerfile, terra, noctalia]
zielgeraet: Lenovo Yoga 920-13IKB, x86_64
vorlage_fuer: Schulungs-PCs Intel/AMD
verifiziert_am: 2026-07-16
verifiziert_gegen: Fedora Sway Atomic 44.20260712.0 (x86_64)
---

# 09 — Build-Umgebung auf dem Yoga

Das Yoga ist x86_64 **und** Zielhardware. Damit entfällt der Umweg über
Disk-Images und VMs: gebautes Image pushen, `bootc switch`, rebooten. Der
kürzeste Weg von der Änderung zur laufenden Maschine.

> [!info] Dieses Dokument begleitet die Einrichtung
> Es ist so geschrieben, dass du es auf dem Yoga öffnest und die Codeblöcke
> der Reihe nach ausführst. Alle Dateien werden über Nushell-Raw-Strings
> angelegt — die Entsprechung zum Shell-Heredoc.

## Nushells Heredoc-Entsprechung

Nushell kennt kein `<<EOF`. Die Entsprechung sind **Raw Strings**:

```nu
r#'
Zeile eins
Zeile "zwei" mit $Dollar und \Backslash
'# | save --force datei.conf
```

| Shell | Nushell | Verhalten |
|---|---|---|
| `cat > f <<'EOF'` | `r#'…'# \| save -f f` | **kein** Variablen-Ersatz |
| `cat > f <<EOF` | `$"…" \| save -f f` | Interpolation mit `($var)` |
| `cat >> f <<'EOF'` | `r#'…'# \| save --append f` | anhängen |

> [!warning] Drei Fallen
> 1. Ein Raw String beginnt direkt nach `r#'`. Steht dort ein Zeilenumbruch,
>    landet er in der Datei. Meist harmlos, bei `/etc/shells` nicht.
> 2. Ein Raw String darf die Sequenz `'#` nicht enthalten. Falls doch:
>    mehr Rauten verwenden — `r##'…'##`.
> 3. **Enthält der Raw String selbst Markdown-Codefences** (wie beim README
>    unten), braucht der *umschließende* Block im Vault vier Backticks —
>    sonst beendet die innere Fence den äußeren Block.
>
> Für sudo-Schreibvorgänge geht `save` nicht (kein Root). Dann:
> `r#'…'# | sudo tee /etc/… | ignore`

> [!important] Grundsatz: welches `save` wann
> | Situation | Befehl | Warum |
> |---|---|---|
> | **Bestehende Config erweitern** (`env.nu`, `config.nu`, `/etc/shells`) | `save --append` **+ Marker-Guard** | Bestand bleibt, kein Doppel-Eintrag |
> | **Eigenes Artefakt anlegen** (`Containerfile`, `terra.repo`, `README.md`, Drop-ins) | `save` **ohne** `--force` | bricht ab, wenn die Datei existiert — genau das ist gewollt |
> | **Bewusst ersetzen** | `save --force` | nur, wenn die Datei nachweislich generiert ist |
>
> `--append` auf ein Artefakt wäre **schlimmer** als `--force`: Ein zweiter
> `FROM`-Block im Containerfile oder eine doppelte `[terra]`-Sektion ergibt
> eine kaputte Datei **ohne** Fehlermeldung. `save` ohne Flag scheitert
> stattdessen laut — und eine laute Fehlermeldung ist die bessere Nachricht.

> [!check] `save` ohne `--force` bricht wirklich ab (verifiziert, Nushell 0.114.1)
> ```
> Error: Destination file already exists
> ```
> Die bestehende Datei bleibt dabei **unverändert**. Für Artefakte braucht es
> also keinen zusätzlichen Guard — der Schutz ist eingebaut.

## Idempotenz: Marker-Guard für Config-Dateien

`--append` schützt den Bestand, aber nicht vor dem **zweiten Durchlauf**. Die
Lösung ist ein Sentinel-Block mit eindeutigem Marker: Ist er schon da, passiert
nichts.

```nu
# Fuegt einen Block nur ein, wenn der Marker noch nicht in der Datei steht.
def ensure-block [
    ziel: path      # Zieldatei
    marker: string  # eindeutige Kennung
    inhalt: string  # einzufuegender Text
] {
    let da = (($ziel | path exists) and (open --raw $ziel | str contains $marker))

    if $da {
        print $"($ziel | path basename): '($marker)' bereits vorhanden - uebersprungen"
        return
    }

    mkdir ($ziel | path dirname)
    $"\n# >>> ($marker) >>>\n($inhalt | str trim)\n# <<< ($marker) <<<\n" | save --append $ziel
    print $"($ziel | path basename): '($marker)' ergaenzt"
}
```

Das Gegenstück — Block sauber wieder herausoperieren:

```nu
def remove-block [ziel: path, marker: string] {
    if not ($ziel | path exists) { print "Datei fehlt"; return }
    let alt = (open --raw $ziel)
    if not ($alt | str contains $marker) { print $"'($marker)' nicht vorhanden"; return }

    # Klammern im Regex escapen -- siehe Warnung unten
    let muster = $"\(?s\)\n?# >>> ($marker) >>>.*?# <<< ($marker) <<<\n?"
    $alt | str replace --regex $muster "" | save --force $ziel
    print $"'($marker)' entfernt"
}
```

> [!warning] `$"..."` wertet `( )` als Subexpression aus
> Ein Regex wie `(?s)` im interpolierten String lässt Nushell nach einem
> Kommando `?s` suchen:
> ```
> Error: Command `?s` not found
> ```
> Deshalb `\(?s\)` — die Klammern escapen. Betrifft **jeden** Regex, der per
> `$"..."` zusammengebaut wird. Alternative: Regex als Raw String `r#'…'#`
> halten und ohne Interpolation arbeiten.

> [!check] Verifiziert am 2026-07-16 gegen Nushell 0.114.1
> Erster Lauf ergänzt, zweiter Lauf überspringt, `remove-block` entfernt den
> Block rückstandsfrei — die vorbestehende Nutzerkonfiguration bleibt in allen
> drei Fällen unangetastet.

---

## Schritt 1 — Preflight: saubere Umgebung verifizieren

> [!info] Zweck
> Zwei Dinge **getrennt** nachweisen: **(A) das System steht auf reiner
> Image-Basis** (Exploration rückstandsfrei) und **(B) die Build-Umgebung ist
> funktionsfähig**. Ergebnisse des Durchlaufs vom 2026-07-16 stehen als
> `[!check]` dabei.

### A — System auf reiner Image-Basis

```nu
bootc status
rpm-ostree status
```

Sauber heißt:

- **`LayeredPackages:`** enthält nur bewusst gesetzte Pakete (Bootstrap, s. Schritt 2)
- **kein `LocalPackages`**, **kein `ReplacedBasePackages`**
- **genau ein Deployment mit `●`**, kein „pending" darüber

Rollback-Deployment mit Exploration-Layern entfernen:

```nu
sudo rpm-ostree cleanup -r
rpm-ostree status
```

> [!warning] Warum das Rollback-Deployment weg muss
> Es ist nicht gebootet und damit harmlos — **aber**: Geht beim ersten
> `bootc switch` etwas schief und du rollst zurück, landest du in der
> Exploration-Umgebung **mit** Noctalia-Layer. Für einen ehrlichen Test
> verwirrend.

> [!check] Erwartete `bootc status`-Ausgabe vor dem ersten Switch: „Booted ostree"
> Das System läuft von einer **ostree-Ref**, noch nicht von einem
> Container-Image — bootc sagt damit „ich verwalte das hier (noch) nicht als
> Image". Der von bootc gemeldete Commit weicht von der `BaseCommit` in
> `rpm-ostree status` ab; das ist kein Widerspruch, sondern die Ebenen:
> rpm-ostree zeigt den **Base**-Commit, bootc den finalen Deployment-Commit
> **inklusive** der gelayerten Pakete.

> [!warning] Switch-Pfad ist versionsabhängig
> `bootc switch` ist der dokumentierte Übergang ostree-Ref → Container-Image.
> Ob er aus dem „Booted ostree"-Zustand in der installierten bootc-Version
> direkt durchläuft, ist **nicht verifiziert**. Fallback:
> ```nu
> sudo rpm-ostree rebase --experimental ostree-unverified-image:containers-storage:quay.io/metarow/noctarow:44
> ```
> Nach dem ersten erfolgreichen Wechsel meldet `bootc status` „Booted image"
> und der reguläre `bootc upgrade`-Pfad steht.

### B — Exploration-Rückstände

```nu
# Terra-Repo-Datei weg?
glob /etc/yum.repos.d/*.repo | path basename

# User-Overrides — maskieren später das Image-Verhalten
glob ($nu.home-path | path join ".config/sway/config.d/*")
glob ($nu.home-path | path join ".config/sway/config")
glob ($nu.home-path | path join ".config/noctalia")
glob ($nu.home-path | path join ".cache/noctalia")
```

> [!warning] Der wichtigste Punkt für einen ehrlichen Image-Test
> `/home` ist **nicht** Teil des Images und überlebt den Switch. Bleiben
> User-Dateien liegen, testest du nach `bootc switch` nicht das Image, sondern
> *Image + Altlasten*. Wegsichern statt löschen — sie sind die Vorlage für die
> Image-Drop-ins:
> ```nu
> let ts = (date now | format date "%Y%m%d")
> mv ($nu.home-path | path join ".config/sway/config.d") ($nu.home-path | path join $".config/sway/config.d.bak-($ts)")
> mv ($nu.home-path | path join ".config/noctalia") ($nu.home-path | path join $".config/noctalia.bak-($ts)")
> rm -rf ($nu.home-path | path join ".cache/noctalia")
> ```

> [!tip] Erkenntnis aus dem Durchlauf: `30-borders.conf` gehört ins Image
> Im Home lag `~/.config/sway/config.d/30-borders.conf`. Ist die
> Border-Einstellung dauerhaft gewollt, gehört sie als Drop-in nach
> `/usr/share/sway/config.d/` ins Containerfile — nicht ins Home. Genau die
> Sorte Erkenntnis, für die die Exploration da war. Siehe
> [[Noctalia auf Sway Atomic – Installation & Konfiguration (Exploration)]].

> [!check] Fehlalarm ausgeräumt: `fedora-workstation-repositories`
> `google-chrome.repo`, `rpmfusion-nonfree-nvidia-driver.repo`,
> `rpmfusion-nonfree-steam.repo` und das PyCharm-COPR stammen **alle** aus dem
> Paket `fedora-workstation-repositories-38-9.fc44`, das **nicht** in
> `LayeredPackages` steht → **Teil des Basis-Images**, keine Altlast. Die
> Definitionen werden mit `enabled=0` ausgeliefert und tun nichts; das
> NVIDIA-Repo ist hardware-unabhängig mitgeliefert. **Nichts zu tun.**
> Herkunft bei Bedarf so klären:
> ```nu
> glob /etc/yum.repos.d/*.repo
> | each {|f| {repo: ($f | path basename), herkunft: (rpm -qf $f | complete | get stdout | str trim)} }
> ```
> „is not owned by any package" = manuell abgelegt → prüfen. Ein Paketname =
> vom Image mitgebracht → ok.

### C — Build-Umgebung

```nu
uname -m                                              # x86_64 auf dem Yoga
sudo podman version
sudo podman info --format '{{.Store.GraphRoot}}'      # → /var/lib/containers/storage
df -h /var                                            # 15–20 GB frei einplanen
which bootc
```

> [!important] Platz auf `/var`
> Das Basis-Image ist ~2,5 GB, jeder Build-Layer kommt dazu. Rechne mit 15 GB
> für Container-Storage. Auf einem 256-GB-Yoga eng, aber machbar.
> `podman system prune -a` ist dein Freund.

> [!warning] `sudo` ist hier kein Detail
> Der Build muss in **root's** `containers-storage` landen, sonst findet
> `bootc switch --transport containers-storage` das Image später nicht. Siehe
> Schritt 7.

> [!note] `podman info` gibt YAML aus
> Deshalb `--format '{{.Store.GraphRoot}}'` (Go-Template) statt `| from json`.
> Für Nushell-Weiterverarbeitung: `sudo podman info --format json | from json`.

Erwartungsbild gegenüber der WSL-Umgebung ([[docs/02-umgebung-wsl]]):

| Prüfung | WSL (XPS) | Yoga |
|---|---|---|
| Mount-Propagation | `shared` (nach wsl.conf-Fix) | `shared` (Standard) |
| `/dev/dri` | fehlt | **vorhanden** |
| SELinux | keiner | **enforcing** |

### D — Trockenlauf

```nu
sudo podman pull quay.io/fedora-ostree-desktops/sway-atomic:44
sudo podman images
```

Zieht das durch, sind Netz, Storage und Arch-Auflösung bestätigt — ein
späterer Fehlschlag liegt dann am Containerfile, nicht an der Umgebung.

---

## Schritt 2 — Werkzeuge: drei Wege

| Weg | Kosten | Wann |
|---|---|---|
| **A** `rpm-ostree install` | Reboot (oder `--apply-live`), Layer bei jedem Update neu aufgelöst | Werkzeuge, die du täglich brauchst |
| **B** `toolbox` / `distrobox` | Container, kein Reboot, aber Podman-in-Podman für Builds | Wegwerf-Umgebungen |
| **C** ins Noctarow-Image aufnehmen | sauber, aber Henne-Ei beim ersten Build | die richtige Endlösung |

**Empfehlung: A zum Bootstrappen, C als Ziel.** Sobald Noctarow selbst
`nushell` und `helix` mitbringt, entfernst du den Layer wieder (Schritt 11).

Weg B taugt hier nicht: `bootc-image-builder` braucht privilegierte Container
und Loop-Devices. Podman-in-Toolbox macht daraus ein Trauerspiel.

```nu
# Weg A -- --apply-live spart den Reboot
sudo rpm-ostree install --apply-live nushell helix gh jq
```

`nu` ist damit sofort verfügbar. Prüfen:

```nu
rpm-ostree status | lines | first 12
```

> [!note] Warum das kein Widerspruch zu bootc ist
> Package Layering ist der vorgesehene Weg für hostspezifische Ergänzungen und
> **zum Bootstrappen**. Es macht das System nicht mutable — der Layer wird bei
> jedem Update deterministisch neu aufgesetzt. Was man vermeiden sollte, ist
> `rpm-ostree override`, und Dateien in `/usr` von Hand anzufassen.
>
> Der Grundsatz „was alle brauchen, gehört ins Image" bleibt davon unberührt:
> Der Bootstrap-Layer ist **temporär und wird in Schritt 11 abgebaut**.

> [!warning] Gelayerte Pakete verschwinden beim Switch
> Der Host-Layer ist Teil der ostree-Deployment-Kette, **nicht** des neuen
> Images. `nushell` muss daher im Containerfile stehen — sonst nach dem Switch
> keine Login-Shell. Ebenfalls beim ersten Boot prüfen: ob die per `chsh`
> gesetzte Login-Shell in `/etc/passwd` den Switch überlebt.

## Schritt 3 — Nushell als Login-Shell

`chsh` fehlt auch hier. Und `usermod` ist auf Atomic der robustere Weg, weil
der WSL-typische passwortlose sudo hier nicht gilt.

```nu
sudo rpm-ostree install --apply-live util-linux-user

# nu in /etc/shells eintragen -- ohne fuehrenden Zeilenumbruch!
which nu | get path.0 | sudo tee -a /etc/shells | ignore

chsh -s (which nu | get path.0)
```

> [!danger] Rückweg
> ```
> ssh fritz@yoga -t /bin/bash
> ```
> oder in der TTY (`Strg+Alt+F3`) anmelden und `chsh -s /bin/bash`.
> Anders als bei WSL gibt es hier kein `wsl -e /bin/bash`.
>
> Wichtiger noch: **`/etc/shells` und `/etc/passwd` liegen in `/etc`.** Auf
> bootc unterliegen sie dem 3-Wege-Merge und überleben `bootc upgrade`. Ein
> kaputter Eintrag überlebt ihn ebenfalls.

Abmelden, neu anmelden.

## Schritt 4 — Nushell-Konfiguration

> [!important] `--append` mit Guard, nicht `--force`
> `env.nu` und `config.nu` **existieren bereits**, sobald `nu` einmal gestartet
> wurde. `save --force` würde sie wortlos platt machen. Hier wird **erweitert**,
> nicht erzeugt. Der Marker-Guard sorgt zusätzlich dafür, dass ein zweiter
> Durchlauf nichts doppelt einträgt. Hintergrund:
> [Idempotenz-Abschnitt](#idempotenz-marker-guard-für-config-dateien).

Der Block ist **selbstenthaltend** — `def` und Aufruf zusammen, damit nichts
vorab in der Session definiert sein muss:

```nu
def ensure-block [
    ziel: path      # Zieldatei
    marker: string  # eindeutige Kennung
    inhalt: string  # einzufuegender Text
] {
    let da = (($ziel | path exists) and (open --raw $ziel | str contains $marker))

    if $da {
        print $"($ziel | path basename): '($marker)' bereits vorhanden - uebersprungen"
        return
    }

    mkdir ($ziel | path dirname)
    $"\n# >>> ($marker) >>>\n($inhalt | str trim)\n# <<< ($marker) <<<\n" | save --append $ziel
    print $"($ziel | path basename): '($marker)' ergaenzt"
}

ensure-block ($nu.default-config-dir | path join "env.nu") "noctarow" r#'
$env.EDITOR = "hx"
$env.VISUAL = "hx"

# Registry-Login dauerhaft ablegen, nicht in XDG_RUNTIME_DIR
$env.REGISTRY_AUTH_FILE = ($nu.home-path | path join ".config/containers/auth.json")

# noctarow-Modul von ueberall importierbar
$env.NU_LIB_DIRS = ($env.NU_LIB_DIRS | append ($nu.home-path | path join "projekte/noctarow/scripts"))
'#

ensure-block ($nu.default-config-dir | path join "config.nu") "noctarow" r#'
$env.config.show_banner = false
'#
```

> [!danger] `use scripts/noctarow.nu *` gehört **noch nicht** in die `config.nu`
> `use` wird zur **Parse-Zeit** aufgelöst — die Moduldatei muss existieren,
> *bevor* irgendetwas ausgeführt wird. Das Projekt entsteht aber erst in
> Schritt 5. Steht die Zeile schon jetzt drin, scheitert jeder Shell-Start:
> ```
> Error: nu::parser::module_not_found
>   help: module files and their paths must be available before your script is
>         run as parsing occurs before anything is evaluated
> ```
> **Und der Parse-Fehler verwirft die komplette `config.nu`** — verifiziert:
> auch `show_banner = false` und alles andere im File ist dann wirkungslos.
> Die Zeile kommt deshalb erst in [Schritt 5](#schritt-5--projekt-holen-oder-anlegen)
> dazu.

> [!note] `NU_LIB_DIRS` auf ein nicht existierendes Verzeichnis ist harmlos
> Der Eintrag in `env.nu` darf jetzt schon stehen — er wird nur bei einem
> `use` ausgewertet und erzeugt für sich genommen keinen Fehler.

> [!warning] `def` gilt nur für die aktuelle Session
> `Command 'ensure-block' not found` heißt: Die Definition fehlt in *dieser*
> Shell. Nach einem Shell-Neustart ist sie wieder weg — deshalb `def` und
> Aufruf immer gemeinsam ausführen. Für dauerhafte Verfügbarkeit gehört der
> Helfer später nach `scripts/helpers.nu` im Projekt und wird per
> `use scripts/helpers.nu *` geladen.

> [!tip] `$nu.default-config-dir` statt `~/.config/nushell`
> Plattformneutral — auf Windows liegt die Konfiguration unter
> `%APPDATA%\nushell`. Siehe [[docs/02-umgebung-wsl]].

Kontrolle, dass der Bestand erhalten und die Datei syntaktisch heil ist:

```nu
open --raw ($nu.default-config-dir | path join "env.nu") | lines | length
nu -c 'echo ok'          # laedt env.nu + config.nu in einer frischen Instanz
```

Rückweg, falls der Block wieder raus soll — `remove-block` aus dem
[Idempotenz-Abschnitt](#idempotenz-marker-guard-für-config-dateien) vorher
definieren:

```nu
remove-block ($nu.default-config-dir | path join "env.nu") "noctarow"
```

> [!caution] `WLR_RENDERER` hier **nicht** setzen
> Auf dem Yoga existiert `/dev/dri`. Software-Rendering zu erzwingen wäre
> genau falsch. Der Wert gehört ausschließlich in die WSL-Umgebung, und dort
> setzt ihn `noctarow test-nested` selbst.

---

## Schritt 5 — Projekt holen oder anlegen

> [!important] Zwei Fälle — nicht beide ausführen
> **5a** wenn `github.com/metarow/noctarow` schon existiert (Regelfall).
> **5b** nur beim allerersten Bootstrap, wenn es das Repo noch nicht gibt.

### 5a — Klonen (Regelfall)

Ab jetzt aus GitHub, nicht mehr als Tarball. Siehe
[[docs/10-github-repository]].

```nu
mkdir ~/projekte
cd ~/projekte
git clone https://github.com/metarow/noctarow.git
cd noctarow
```

Prüfen, dass das Modul greift:

```nu
use scripts/noctarow.nu *
noctarow doctor
```

### Modul dauerhaft verfügbar machen

**Erst jetzt** — das Projekt existiert, `use` ist zur Parse-Zeit auflösbar
(siehe die Warnung in Schritt 4). `NU_LIB_DIRS` zeigt bereits auf
`~/projekte/noctarow`, deshalb reicht der relative Pfad:

```nu
ensure-block ($nu.default-config-dir | path join "config.nu") "noctarow-modul" r#'
use scripts/noctarow.nu *
'#

nu -c 'noctarow doctor'    # frische Instanz -- laedt config.nu neu
```

> [!check] Verifiziert (Nushell 0.114.1)
> `$env.NU_LIB_DIRS` aus der `env.nu` greift für ein `use` in der `config.nu`
> — ein `const NU_LIB_DIRS` ist nicht nötig. Der relative Pfad
> `scripts/noctarow.nu` wird gegen die `NU_LIB_DIRS`-Einträge aufgelöst.
> Ebenfalls möglich, aber ohne `NU_LIB_DIRS`-Abhängigkeit:
> `use ~/projekte/noctarow/scripts/noctarow.nu *` — die Tilde wird expandiert.

> [!warning] Preis der Bequemlichkeit
> Steht `use` in der `config.nu`, **muss** das Projekt bei jedem Shell-Start
> vorhanden sein. Verschiebst oder löschst du `~/projekte/noctarow`, scheitert
> der Start und die **gesamte** `config.nu` wird verworfen. Rückweg:
> ```nu
> remove-block ($nu.default-config-dir | path join "config.nu") "noctarow-modul"
> ```
> Wer das nicht will, lässt die Zeile weg und ruft `use scripts/noctarow.nu *`
> pro Session im Projektverzeichnis auf.

### 5b — Neu anlegen (nur beim ersten Bootstrap)

> [!warning] Strukturkompatibel, nicht auf der grünen Wiese
> `sway/70-output.conf`, `sway/50-keyboard.conf`, `foot/foot.ini`,
> `hosts/yoga920/` und `scripts/` existieren im Projekt bereits. Die Befehle
> unten legen die **fehlenden** Dateien an. `save` ohne `--force` überschreibt
> nicht — bestehende Dateien bleiben unangetastet und melden einen Fehler, den
> man bewusst prüfen sollte.

#### Zielstruktur

```
~/projekte/noctarow/
├── Containerfile
├── README.md
├── terra.repo                  # gevendort, kein curl im Build
├── sway/
│   ├── 30-borders.conf         # NEU — aus dem Home übernommen
│   ├── 50-keyboard.conf        # bestehend — Kernbefund, siehe 01
│   ├── 70-output.conf          # bestehend (eDP-1 scale 1.5)
│   ├── 90-bar.conf             # NEU — leer, verdrängt waybar
│   ├── 90-swayidle.conf        # NEU — leer, verdrängt swayidle
│   ├── 95-noctalia.conf        # NEU — Autostart Noctalia
│   └── environment.noctarow    # bestehend
├── foot/
│   └── foot.ini                # bestehend
├── sddm/                       # bestehend — HiDPI/Tastatur Login-Screen
├── tmpfiles/                   # bestehend — First-Boot-Auslieferung
├── hosts/yoga920/
│   ├── 50-keyboard.conf        # bestehend
│   ├── 70-output.conf          # bestehend
│   └── kanshi-config           # bestehend
└── scripts/                    # bestehend
```

#### Verzeichnisse

```nu
cd ($nu.home-path | path join "projekte")
mkdir noctarow/sway noctarow/foot noctarow/hosts/yoga920
cd noctarow
```

(Nushells `mkdir` legt Elternverzeichnisse automatisch an — kein `-p` nötig.)

#### `terra.repo`

Inhalt aus dem Terra-Upstream (`subatomic-repos`), bewusst als **Datei im
Git** statt `http get` im Build:

```nu
r#'[terra]
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
'# | save terra.repo
```

> [!warning] Bewusste Abweichung vom Upstream: `skip_if_unavailable=False`
> Upstream liefert `True` aus. Im Build ist das gefährlich: Ist Terra kurz
> nicht erreichbar, würde dnf das Repo **stillschweigend überspringen** und der
> Build je nach Lage ohne Noctalia „erfolgreich" durchlaufen. `False` lässt den
> Build stattdessen laut scheitern.

> [!note] Vendoring ≠ Versions-Pinning
> Die Datei im Git gibt dir Kontrolle über **Repo-Änderungen** und Transparenz
> — nicht über die Paketversion. Echtes Pinning bräuchte ein
> versionsgebundenes `dnf install noctalia-shell-4.7.7`. Bewusste Entscheidung:
> derzeit ungepinnt, dafür aktuell.

#### Drop-ins

```nu
"exec qs -c noctalia-shell\n" | save sway/95-noctalia.conf

# Leere Dateien gleichen Namens verdrängen die Image-Defaults
"" | save sway/90-bar.conf
"" | save sway/90-swayidle.conf
```

> [!warning] Dateinamen vor dem Build live verifizieren
> Der Bar-Snippet heißt derzeit `90-bar.conf`, kann sich je nach
> `sway-config-fedora`-Version ändern. Auf dem laufenden System bestätigen:
> ```nu
> (glob /usr/share/sway/config.d/*.conf) ++ (glob /etc/sway/config.d/*.conf)
> | filter {|f| open --raw $f | str contains waybar }
> ```

> [!warning] Es ist **waybar**, nicht swaybar
> [[docs/01-erkenntnisse#Kollisionen mit Noctalia]] nennt `90-bar.conf` als
> „startet swaybar" — das ist **falsch** und in 01 zu korrigieren. Fedora
> startet **waybar** als eigenständigen Prozess per `exec`. Folge: `swaymsg bar
> mode invisible` wirkt **nicht** (es gibt keinen `bar {}`-Block,
> `swaymsg -t get_bar_config` liefert `[]`). Der leere gleichnamige Override
> ist der richtige Weg — die Methode aus 01 stimmt, nur die Begründung nicht.

`30-borders.conf` aus dem Home-Backup übernehmen (Inhalt vorher sichten):

```nu
let ts = (date now | format date "%Y%m%d")
open --raw ($nu.home-path | path join $".config/sway/config.d.bak-($ts)/30-borders.conf")
| save sway/30-borders.conf
```

#### `Containerfile`

```nu
r#'FROM quay.io/fedora-ostree-desktops/sway-atomic:44

# Terra (Fyra Labs): Quelle für noctalia-shell + noctalia-qs, baut für x86_64 und aarch64.
# Gevendort statt per curl geholt -> nachvollziehbar im Git.
COPY terra.repo /etc/yum.repos.d/terra.repo

# noctalia-qs verlangt Qt 6.11; dnf hebt qt6-qtbase als normale Abhängigkeit an.
# Das "eingefrorene Basis-Paket"-Problem von rpm-ostree install existiert hier nicht.
RUN dnf install -y \
        noctalia-shell \
        nushell \
        helix \
    && dnf clean all \
    && rm -rf /var/cache/libdnf5 /var/cache/dnf

# Sway-Drop-ins nach /usr/share: Dateiname = Identität, Prefix = Ladereihenfolge.
# Leere 90-*-Dateien verdrängen waybar und swayidle (Kollision mit Noctalia).
COPY sway/30-borders.conf    /usr/share/sway/config.d/30-borders.conf
COPY sway/50-keyboard.conf   /usr/share/sway/config.d/50-keyboard.conf
COPY sway/70-output.conf     /usr/share/sway/config.d/70-output.conf
COPY sway/90-bar.conf        /usr/share/sway/config.d/90-bar.conf
COPY sway/90-swayidle.conf   /usr/share/sway/config.d/90-swayidle.conf
COPY sway/95-noctalia.conf   /usr/share/sway/config.d/95-noctalia.conf

COPY sway/environment.noctarow /usr/share/sway/environment

# foot liest die System-Default über $XDG_CONFIG_DIRS, nicht /usr/share
COPY foot/foot.ini /etc/xdg/foot/foot.ini

# Login-Screen: HiDPI + Tastatur
COPY sddm/    /usr/lib/sddm/sddm.conf.d/
COPY tmpfiles/ /usr/lib/tmpfiles.d/

RUN bootc container lint
'# | save Containerfile
```

> [!check] Konfliktauflösung: `/usr/share` statt `/etc` für die leeren Overrides
> Die Ergänzung schlug `COPY sway/90-bar.conf /etc/sway/config.d/90-bar.conf`
> vor — das setzt voraus, dass `/etc` das `/usr/share`-Pendant überschattet,
> was **nicht verifiziert** ist. [[docs/01-erkenntnisse#Kollisionen mit
> Noctalia]] hat das bereits entschieden: *„Weil wir das Image selbst bauen,
> überschreiben wir die Dateien direkt in `/usr/share` — kein `/etc`-Umweg,
> kein Merge-Risiko."* Dieser Weg ist übernommen. `/etc` bleibt frei für
> maschinenspezifische Abweichungen (Schritt 10).

> [!warning] `bootc container lint` setzt bootc im Image voraus
> Bei Fedora-Atomic-Basisimages üblich, aber nicht geprüft. Scheitert der
> Schritt, Zeile entfernen — sie ist eine Qualitätsprüfung, keine
> Funktionsbedingung.

> [!warning] `kanshi`, `matugen`, `cliphist`, `quickshell`
> Die Ergänzung listete `kanshi matugen cliphist` im `dnf install`.
> [[docs/05-hidpi-und-monitore]] sagt, `kanshi` sei **bereits im Image**.
> Vor dem Build live prüfen und nur ergänzen, was fehlt:
> ```nu
> ["kanshi" "matugen" "cliphist"] | each {|p| {paket: $p, da: (rpm -q $p | complete | get exit_code | $in == 0)} }
> ```
> **`quickshell` nicht installieren** — `noctalia-qs` kollidiert damit
> (gleiche Provides). Das korrigiert die ältere Annahme aus
> [[docs/07-referenz-quellen]].

#### `README.md`

Beachte die **vier** Backticks außen — der Inhalt enthält selbst Codefences:

````nu
r#'# Noctarow

Custom bootc/OCI-Image auf Basis von Fedora Sway Atomic 44.
Ziel-Registry: `quay.io/metarow/noctarow`
Primäre Zielhardware: Lenovo Yoga 920-13IKB (x86_64, 4K, Intel UHD 620)

Betreiber: MetaRow Software UG

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
'# | save README.md
````

#### Kontrolle

```nu
ls **/* | select name type size
git status --short
```

---

## Schritt 6 — SELinux

Das ist der Unterschied, der dich sonst eine Stunde kostet. Bind-Mounts in
Container brauchen ein Label:

```nu
# falsch auf Atomic:  -v /pfad:/ziel
# richtig:            -v /pfad:/ziel:Z
```

`noctarow test-nested` nutzt bereits `--security-opt label=disable` für den
Wayland-Socket. Das ist für einen Testcontainer vertretbar. Für alles andere
gilt `:Z`.

Falls etwas unerklärlich fehlschlägt:

```nu
sudo ausearch -m avc -ts recent | tail -30
```

Nicht reflexhaft `setenforce 0`. Das verdeckt das Problem, und auf einer
Schulungsmaschine ist es die falsche Gewohnheit.

## Schritt 7 — Bauen

```nu
noctarow build --tag 44
```

Das Ergebnis: `quay.io/metarow/noctarow:44-amd64` und `localhost/noctarow:44`.

> [!warning] Rootless vs. rootful — vor dem ersten Switch klären
> `noctarow build` baut vermutlich **rootless**. Für
> `bootc switch --transport containers-storage` (Schritt 9, Weg B) muss das
> Image aber in **root's** Storage liegen. Beides ist **nicht verifiziert**.
> Prüfen:
> ```nu
> podman images | where repository =~ noctarow        # rootless-Storage
> sudo podman images | where repository =~ noctarow   # root-Storage
> ```
> Steht es nur im rootless-Storage, entweder direkt mit `sudo podman build`
> bauen oder `noctarow.nu` entsprechend anpassen. Fällt das weg, wenn du über
> die Registry gehst (Weg A).

## Schritt 8 — Testen, ohne zu rebooten

Du sitzt in einer Sway-Session mit echter GPU. Der nested Test läuft hier
**hardwarebeschleunigt**:

```nu
noctarow test-nested --tag 44
```

Ein Sway-Fenster in deinem Sway. Darin Noctalia. Kein `pixman`, keine
Ruckelei — hier siehst du zum ersten Mal, wie das Ding wirklich aussieht.

```nu
# im nested Sway:
noctarow keyboard-check
noctarow output-check
pgrep -al waybar        # muss LEER sein — sonst greift der 90-bar-Override nicht
pgrep -a qs             # Noctalia lebt
```

## Schritt 9 — Ausrollen auf dieselbe Maschine

Jetzt der Moment, für den bootc gebaut wurde. Zwei Wege:

**Weg A — über die Registry** (der Flottenweg, siehe
[[docs/04-quay-veroeffentlichung]]):

```nu
noctarow push --tag 44
sudo bootc switch quay.io/metarow/noctarow:44-amd64
systemctl reboot
```

**Weg B — lokal, ohne Push** (schneller für den allerersten Test):

```nu
sudo bootc switch --transport containers-storage quay.io/metarow/noctarow:44-amd64
systemctl reboot
```

> [!important] Kein `:latest`
> Die Ergänzung nutzte `:latest`. Das widerspricht der Tag-Strategie aus
> [[docs/04-quay-veroeffentlichung#Tag-Strategie]] — Floating-Tags sind für die
> Flotte ausdrücklich ausgeschlossen. Auch lokal konsistent bei `44-amd64`
> bleiben, damit Registry- und Lokalpfad dasselbe Artefakt benennen.

> [!tip] Vorher den Rückweg üben
> ```nu
> bootc status                # zeigt Rollback-Deployment
> sudo bootc rollback
> systemctl reboot
> ```
> Wer Rollback zum ersten Mal im Ernstfall probiert, probiert es falsch.

Nach dem Reboot bist du in deinem eigenen Image. `bootc status` zeigt das alte
Deployment als Rollback-Ziel — es liegt noch da, nichts wurde überschrieben.

## Schritt 10 — Hostspezifisches nachlegen

```nu
noctarow apply-host yoga920
swaymsg reload
```

Legt `70-output.conf` (Skalierung) und `50-keyboard.conf` nach
`/etc/sway/config.d/`, wo sie die Image-Defaults verdrängen. Und das
kanshi-Profil nach `~/.config/kanshi/config`.

Danach:

```nu
noctarow output-check
```

> [!warning] Konflikt: `scale 2` vs. `scale 1.5` — zu klären
> Diese Note sagte bisher „Bei der 4K-Variante muss dort `scale: 2` stehen".
> Die aktuelle Projektentscheidung ist jedoch **fraktional `scale 1.5`**
> (XWayland-Unschärfe bewusst akzeptiert, Rückweg auf `2` falls eine
> Schulungsflotte Ziel wird). Erwarteter Wert ist damit **`scale: 1.5`**.
> Gegenprüfen gegen `hosts/yoga920/70-output.conf` und
> [[docs/05-hidpi-und-monitore]] — auch dort steht in der Empfehlungstabelle
> noch `scale 2`.

## Schritt 11 — Layer wieder abbauen

Sobald Noctarow selbst `nushell` und `helix` mitbringt — und das tut es laut
Containerfile oben:

```nu
sudo rpm-ostree uninstall nushell helix jq gh util-linux-user
systemctl reboot
```

Weniger Layer heißt schnellere Updates und weniger Abhängigkeitsauflösung bei
jedem `bootc upgrade`. Das ist der eigentliche Gewinn von bootc: **was alle
brauchen, gehört ins Image; was nur diese Maschine braucht, nach `/etc`.**

> [!note] Nach dem Switch meist gegenstandslos
> Gelayerte Pakete sind an die ostree-Deployment-Kette gebunden und
> verschwinden mit dem Wechsel auf das Container-Image ohnehin. Dieser Schritt
> ist der saubere Weg, **falls** du vor dem Switch aufräumen willst — oder
> falls nach dem Switch doch noch Layer auftauchen.

---

## Prüfliste

```nu
bootc status
rpm-ostree status | lines | first 8
sudo podman images | where repository =~ noctarow
noctarow doctor
noctarow keyboard-check
noctarow output-check                          # scale 1.5 erwartet — s. Schritt 10
systemctl --user status sway-session.target
pgrep -a qs                                    # Noctalia läuft
pgrep -al waybar                               # muss leer sein
rpm -q noctalia-shell                          # v4.7.x — Sway-Workspace-Backend
```

## Aufgaben

- [x] `rpm-ostree status` — nur `nushell` gelayert, kein `ReplacedBasePackages` (2026-07-16)
- [x] `sudo rpm-ostree cleanup -r` — Rollback-Deployment entfernt (2026-07-16)
- [x] `sudo bootc status` — „Booted ostree" (2026-07-16)
- [ ] User-Dateien wegsichern (`config.d`, `.config/noctalia`, `.cache/noctalia`)
- [ ] `30-borders.conf` Inhalt sichten und ins Projekt übernehmen
- [ ] Build-Umgebung prüfen (`podman version`, `df -h /var`, GraphRoot)
- [ ] Trockenlauf: Basis-Image pullen
- [ ] Projektverzeichnis vervollständigen (`terra.repo`, `Containerfile`, `README.md`, Drop-ins)
- [ ] **Erst nach Schritt 5:** `use scripts/noctarow.nu *` in die `config.nu` nachtragen
- [ ] waybar-Snippet-Dateinamen live verifizieren (glob/filter)
- [ ] `kanshi`/`matugen`/`cliphist` — prüfen, was das Basis-Image schon mitbringt
- [ ] **Klären: `scale 2` oder `scale 1.5`?** — Widerspruch zu [[docs/05-hidpi-und-monitore]]
- [ ] **Klären: baut `noctarow build` rootless oder rootful?**
- [ ] [[docs/01-erkenntnisse]] korrigieren: `90-bar.conf` startet **waybar**, nicht swaybar
- [ ] [[docs/07-referenz-quellen]] korrigieren: `quickshell` kollidiert mit `noctalia-qs`
- [ ] Erster Build und Switch
- [ ] Nach erstem Boot: `pgrep -al waybar` leer? Login-Shell noch Nushell?

## Verwandte Notizen

- [[docs/01-erkenntnisse]]
- [[docs/04-quay-veroeffentlichung]]
- [[docs/05-hidpi-und-monitore]]
- [[docs/06-lenovo-yoga-deployment]]
- [[docs/10-github-repository]]
- [[Noctalia auf Sway Atomic – Installation & Konfiguration (Exploration)]]


Naechster Schritt -- bewusst selbst ausfuehren:
  sudo bootc switch --transport containers-storage localhost/noctarow:44
  sudo systemctl reboot

Rueckweg, falls der neue Stand nicht taugt:
  sudo bootc rollback
  sudo systemctl reboot