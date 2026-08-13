---
titel: Verteilung — was liegt wo
teil_von: "[[README]]"
tags: [wsl, windows, dateisystem, ext4, drvfs, hyperv, obsidian]
---

# 08 — Verteilung: Windows- und WSL-Seite

## Der Grundsatz

Das Projekt lebt **vollständig im ext4-Dateisystem der WSL-Distro**. Die
Windows-Seite bekommt genau zwei Dinge: das Steuerungsmodul und die fertige
VHDX.

> [!danger] Nicht unter `/mnt/c` bauen
> Ein Podman-Build unter `/mnt/c` läuft über 9p/drvfs. Das ist nicht nur
> langsam — Linux-Dateirechte, Hardlinks und Overlay-Layer funktionieren dort
> nicht zuverlässig. `bootc container lint` schlägt fehl oder das Image
> enthält falsche Rechte.
>
> `noctarow disk` prüft das Dateisystem und bricht ab, wenn es nicht `ext4`
> ist.

## Übersicht

| Was | Wo | Warum |
|---|---|---|
| Gesamtes Repo | `~/projekte/noctarow` (**WSL, ext4**) | Build-Performance, Dateirechte |
| `scripts/noctarow.nu` | dort, Teil des Repos | wird in WSL ausgeführt |
| `scripts/noctarow-win.nu` | **Kopie** nach `~/.config/nushell/scripts/` (Windows) | Nushell auf dem Host lädt es |
| `output/disk.raw`, `*.vhdx` | erzeugt in WSL (ext4) | Loop-Devices |
| Fertige VHDX | kopiert nach `C:\Hyper-V\noctarow\` (**NTFS**) | Hyper-V liest keine VHDX von `\\wsl.localhost` |
| Obsidian-Vault | Windows | siehe unten |

## Einrichten — automatisch

Das Archiv `noctarow.tar.gz` ist die **einzige vollständige Quelle**. Eine
flache Ablieferung einzelner Dateien ist strukturell unmöglich, weil das
Projekt bewusst gleichnamige Dateien in verschiedenen Verzeichnissen führt:

| | |
|---|---|
| `sway/50-keyboard.conf` | ↔ `hosts/yoga920/50-keyboard.conf` |
| `sway/70-output.conf` | ↔ `hosts/yoga920/70-output.conf` |

Das ist kein Versehen — **gleicher Basename bedeutet Verdrängung**, siehe
[[docs/01-erkenntnisse#Das dreistufige Include-System]].

Daher, in Nushell auf Windows, im Download-Ordner:

```nu
nu bootstrap-noctarow.nu --dry-run                        # erst zeigen
nu bootstrap-noctarow.nu --distro FedoraLinux-44 --user fritz
```

Das Skript:

1. entpackt nach `/home/<user>/projekte/noctarow` **in der WSL-Distro**
2. prüft, dass dort `ext4` liegt und nicht `9p`/`drvfs`
3. legt einen initialen Git-Commit an
4. kopiert `noctarow-win.nu` nach `~/.config/nushell/scripts/`

Danach ist `bootstrap-noctarow.nu` im Download-Ordner überflüssig — eine
versionierte Kopie liegt im Repo unter `scripts/`.

> [!note] Was das Skript bewusst nicht tut
> Es schreibt nicht in deine `config.nu`. Die `use`-Zeile fügst du selbst ein.
> Ein Werkzeug, das ungefragt in Shell-Konfigurationen schreibt, ist ein
> Werkzeug, dem man beim nächsten Mal nicht mehr traut.

## Einrichten — von Hand

### WSL-Seite

Der Tarball landet beim Download unter Windows. Von dort in WSL entpacken —
**nicht unter `/mnt/c` entpacken und dann kopieren**, sondern direkt ins
Home-Verzeichnis:

```nu
mkdir ~/projekte
cd ~/projekte
tar xzf /mnt/c/Users/fritz/Downloads/noctarow.tar.gz
cd noctarow

# Kontrolle: muss ext4 sein, nicht 9p oder drvfs
df -T . | lines | last

git init
git add -A
git commit -m "Initialer Stand"
```

Modul dauerhaft verfügbar machen, in `~/.config/nushell/config.nu`:

```nu
$env.NU_LIB_DIRS = ($env.NU_LIB_DIRS | append "/home/fritz/projekte/noctarow")
```

Dann reicht im Projektverzeichnis `use scripts/noctarow.nu *`.

### Windows-Seite

Nur das eine Modul:

```nu
mkdir ~/.config/nushell/scripts
cp \\wsl.localhost\FedoraLinux-44\home\fritz\projekte\noctarow\scripts\noctarow-win.nu ~/.config/nushell/scripts/
```

In `~/.config/nushell/config.nu` auf Windows:

```nu
use ~/.config/nushell/scripts/noctarow-win.nu *
```

> [!tip] Kopie statt UNC-Import
> `use \\wsl.localhost\...\noctarow-win.nu *` funktioniert, lädt aber bei jedem
> Shell-Start über 9p und blockiert, wenn die WSL-Distro schläft. Ein
> Windows-Prompt, der auf eine startende VM wartet, nervt nach dem dritten Mal.
> Das Modul ändert sich selten — eine Kopie ist der bessere Handel.

Bei Änderungen am Modul einfach neu kopieren:

```nu
cp (nw path)\scripts\noctarow-win.nu ~/.config/nushell/scripts/
```

## Der VHDX-Weg

Zweistufig, und beide Stufen sind erzwungen:

1. **In WSL erzeugen.** `bootc-image-builder` braucht Loop-Devices im
   privilegierten Container, `qemu-img` braucht das Rohimage. Beides geht nur
   auf ext4.
2. **Auf NTFS kopieren.** Hyper-V kann keine virtuelle Festplatte von
   `\\wsl.localhost` anhängen.

```nu
# Windows-Nushell — erledigt beides
nw sync-vhdx --tag 44
nw vm-create --tag 44
nw vm-start
```

Was `nw sync-vhdx` intern tut:

```nu
nw run "noctarow disk --tag 44"     # WSL: disk.raw → noctarow-44.vhdx
wsl -d FedoraLinux-44 -- cp output/noctarow-44.vhdx /mnt/c/Hyper-V/noctarow/
```

> [!note] Kopierrichtung
> Der `cp` läuft **WSL-seitig** über drvfs, nicht Windows-seitig über
> `\\wsl.localhost`. Das ist deutlich schneller und stolpert nicht über
> Berechtigungen.

## Konstanten anpassen

In `scripts/noctarow-win.nu` oben:

```nu
const PROJEKT  = "/home/fritz/projekte/noctarow"   # WSL-Pfad, absolut!
const DISTRO   = "FedoraLinux-44"
const VHDX_DIR = 'C:\Hyper-V\noctarow'
```

> [!warning] `PROJEKT` ist ein Linux-Pfad
> Er geht an `wsl --cd`. Eine Tilde wird dort **nicht** expandiert —
> `~/projekte/noctarow` schlägt fehl. Absoluter Pfad.

## Obsidian

Der Vault liegt vermutlich auf Windows, die Doku im WSL-Repo. Drei Wege, ehrlich
abgewogen:

| Weg | Vorteil | Nachteil |
|---|---|---|
| Vault-Ordner per UNC öffnen | keine Duplikate | Obsidians Dateiwächter ist über 9p träge und verliert gelegentlich Änderungen |
| **Repo zusätzlich auf Windows klonen**, Git als Sync | sauber, schnell, versioniert | pushen/pullen nötig |
| Symlink WSL → Windows-Vault | Doku direkt im Vault | Docs liegen dann auf 9p, `git status` in WSL wird zäh |

**Empfehlung: Option 2.** Das Repo ist ohnehin die Quelle der Wahrheit, und ein
`git push` nach einem Doku-Update ist kein Preis. Zum Schreiben in Obsidian
arbeitest du auf dem Windows-Klon, zum Bauen in WSL.

## Prüfliste

```nu
# Windows
nw distros
nw path
nw doctor

# WSL
df -T ~/projekte/noctarow | lines | last    # ext4
findmnt -n -o PROPAGATION /                 # shared
```
