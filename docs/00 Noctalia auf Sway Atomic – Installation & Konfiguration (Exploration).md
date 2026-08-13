---
titel: Noctalia auf Sway Atomic – Installation & Konfiguration (Exploration)
aliases: [Noctalia installieren, Noctalia Sway Atomic, Noctalia Exploration]
tags: [fedora, sway-atomic, noctalia, quickshell, noctalia-qs, terra, bootc, noctarow, wayland, exploration]
erstellt: 2026-07-13
system: Fedora Sway Atomic 44
status: entwurf
---

# Noctalia auf Sway Atomic – Installation & Konfiguration (Exploration)

> [!info] Ziel & Kontext
> Vor dem ersten Noctarow-Image auf dem Yoga wird Noctalia **auf dem laufenden Sway Atomic** installiert und angeschaut, um Paketnamen, Config-Layout und Sway-spezifisches Verhalten zu klären. Die Erkenntnisse wandern anschließend ins Containerfile – dieser Durchlauf ist reine Vorarbeit, kein Dauerzustand. Siehe [[09-yoga-buildumgebung]].

> [!warning] Atomic-Disziplin: Wegwerf-Layer
> Auf dem laufenden Atomic-System gibt es zum Ausprobieren nur `rpm-ostree install` – also **Layering**, das den sauberen `bootc upgrade`-Pfad bricht. Das ist hier akzeptabel, weil es ein **Wegwerf-Layer** ist: anschauen → notieren → `rpm-ostree reset`/`uninstall` → alles ins Containerfile. Nichts davon ist der finale Weg fürs Image.

## Was sich gegenüber den bisherigen Notizen geändert hat

> [!warning] Version-abhängig – vor dem Image gegenprüfen
> Noctalia v4 nutzt inzwischen einen **eigenen Quickshell-Fork `noctalia-qs`**, der mit dem offiziellen Fedora-`quickshell` **kollidiert** (gleiche Provides, nicht gleichzeitig installierbar). Der bisher notierte Weg „`quickshell` aus dem Fedora-Repo" trägt für v4 damit vermutlich **nicht mehr** – es braucht `noctalia-qs`.

- **Offizieller Fedora-Weg ist Terra** (Fyra Labs): Das Paket `noctalia-shell` zieht `noctalia-qs` + alle Runtime-Deps automatisch. Terra baut auch für **aarch64** → löst das alte arm64-Problem des `zhangyi6324`-COPR.
- **Terra ist Drittanbieter.** Für die Exploration unkritisch; fürs Image ein Supply-Chain-Abwägungspunkt (siehe [Übersetzung ins Noctarow-Image](#übersetzung-ins-noctarow-image)).

## Installation (Wegwerf-Layer)

Terra-Repo-Datei nach `/etc/yum.repos.d/` (auf Atomic beschreibbar, passt zur `/etc/`-Präferenz), dann layern. Die Repo-Datei bringt `gpgcheck=1` + `gpgkey`-URL mit – kein `--nogpgcheck` nötig:

```nu
http get https://raw.githubusercontent.com/terrapkg/subatomic-repos/main/terra.repo | sudo tee /etc/yum.repos.d/terra.repo | ignore

sudo rpm-ostree install terra-release noctalia-shell
```

Danach **einmal rebooten** – rpm-ostree-Layer werden erst im nächsten Boot aktiv:

```nu
sudo systemctl reboot
```

> [!note] Ein Reboot genügt
> `terra-release` (Key + persistente Repo-Config) und `noctalia-shell` laufen in einer Transaktion. Die manuell platzierte `terra.repo` ist bereits aktiv, deshalb findet rpm-ostree `noctalia-shell` sofort. Meckert die GPG-Prüfung, ist der `gpgkey=`-Eintrag in `/etc/yum.repos.d/terra.repo` die Stelle zum Prüfen.

## Installierte Version prüfen

Der Sway-Workspace-Backend kam erst **im Laufe der v4-Serie** dazu – daher unbedingt die installierte Version verifizieren. Maßgeblich ist die **Paketversion** (`noctalia-shell`), nicht `qs --version`:

```nu
# Alle gelayerten Pakete anzeigen
rpm-ostree status

# Volle NVR von Noctalia
rpm -q noctalia-shell

# Nur die Version (z. B. 4.7.7)
rpm -q --queryformat '%{VERSION}\n' noctalia-shell
```

> [!warning] `qs --version` ≠ Noctalia-Version
> `qs --version` liefert die Version des **noctalia-qs / Quickshell-Runtimes**, nicht die der Noctalia-Shell. Für die Frage „ist der Sway-Backend drin?" zählt die **`noctalia-shell`-Paketversion**.

Kompakter Versions-Gate in Nushell (native Idiome), der direkt sagt, ob der Sway-Backend vorhanden ist:

```nu
let ver = (rpm -q --queryformat '%{VERSION}' noctalia-shell)
let parts = ($ver | split row '.')
let major = ($parts | get 0 | into int)
let minor = ($parts | get 1 | into int)

if $major == 4 and $minor >= 7 {
    print $"Noctalia ($ver) – Sway-Workspace-Backend vorhanden ✓"
} else {
    print $"Noctalia ($ver) – zu alt für Sway-Workspaces, bitte aktualisieren"
}
```

> [!check] Am Quellcode verifiziert (v4.7.7, höchster v4-Tag)
> In v4.7.7 existiert `Services/Compositor/SwayService.qml` (i3-IPC via `import Quickshell.I3`), erkannt über `SWAYSOCK`. Es liefert ein echtes `workspaces`-ListModel inkl. Fokus-Tracking und Fenster-zu-Workspace-Mapping. Das Bar-Widget `Modules/Bar/Widgets/Workspace.qml` konsumiert `CompositorService.workspaces` **compositor-agnostisch** und ruft `switchToWorkspace()` → Anzeige **und** Klick-zum-Wechseln funktionieren auf Sway.

## Starten – ohne die Sway-Config anzufassen

Für den ersten Blick **nichts** an Sway ändern. In laufender Sway-Session ein foot öffnen und manuell starten:

```nu
qs -c noctalia-shell
```

Der Shell-Layer (Bar, Panels, Launcher, Workspace-Indikator) erscheint. Beenden = das Kommando im Terminal abbrechen. So bleibt das System unangetastet.

> [!warning] Black-Screen-Falle vermeiden
> **Keine** Top-Level-`~/.config/sway/config` anlegen (auch nicht leer) – Sway überspringt dann die System-Default komplett → schwarzer Bildschirm. Autostart erst später als Drop-in setzen, siehe [Image-Abschnitt](#übersetzung-ins-noctarow-image).

## Konfiguration ansehen

| Zweck | Pfad |
|---|---|
| Shell-QML (aus Terra-Paket, system-weit) | `/etc/xdg/quickshell/noctalia-shell/` |
| Deine Settings (JSON, von der Shell geschrieben) | `~/.config/noctalia/` |
| Cache / Wallpaper etc. | `~/.cache/noctalia/` |

```nu
ls ~/.config/noctalia
open ~/.config/noctalia/settings.json
ls /etc/xdg/quickshell/noctalia-shell
```

Konfiguriert wird primär über das **Settings-Panel in der laufenden Shell** (nicht durch Handeditieren) – es schreibt nach `~/.config/noctalia/`.

> [!tip] Theming-Env (qt6ct/Kvantum-Kontext)
> Für konsistentes Icon-/Theming-Verhalten sind zwei Env-Variablen relevant. Für die Exploration reicht ein temporäres Setzen via `with-env`; fürs Image system-weit (`/etc/environment` bzw. Sway-`env`).
> ```nu
> with-env { QT_QPA_PLATFORMTHEME: gtk3 } { qs -c noctalia-shell }
> ```
> Icon-Theme danach mit `nwg-look` wählen. Der Quickshell-IPC-Quirk erlaubt zudem `QT_QPA_PLATFORM=wayland;xcb` (IPC-Calls funktionieren damit korrekt).

## Sway-Workspace-Indikator

> [!check] Frühere Warnung zurückgezogen
> Die ältere Doku-Zeile „Workspace-Indikatoren nur für Niri und Hyprland" ist **veraltet**. In v4.7.7 ist Sway ein vollwertiges Backend (i3-IPC). Der Indikator kann fest ins Sway-basierte Noctarow-Image eingeplant werden. Für nicht erkannte Compositors gibt es zusätzlich einen generischen `ext-workspace-v1`-Fallback (`ExtWorkspaceService.qml`) – Sway nutzt aber sein spezifisches i3-Backend.

## Aufräumen (Wegwerf-Layer entfernen)

```nu
sudo rpm-ostree uninstall noctalia-shell terra-release
sudo rm /etc/yum.repos.d/terra.repo
sudo systemctl reboot
```

> [!note] `reset` vs. `uninstall`
> `rpm-ostree uninstall` ist chirurgisch (entfernt nur diese Layer). `sudo rpm-ostree reset` würde **alle** Layer + lokalen Overrides entfernen – nur nehmen, wenn sonst nichts gelayert ist.

## Übersetzung ins Noctarow-Image

Fürs Image **nicht** `rpm-ostree`, sondern – bootc-Images bauen mit `dnf` zur Build-Zeit – die **gepinnte** Repo-Datei vendorn und installieren (Repo-Datei im Git, kein `curl` im Build → reproduzierbar):

```dockerfile
# terra.repo liegt versioniert im Projekt-Repo
COPY terra.repo /etc/yum.repos.d/terra.repo
RUN dnf install -y noctalia-shell && dnf clean all
```

Autostart als System-Drop-in im Sway-Layered-Include (numerischer Prefix = Ladereihenfolge, `/usr/share/`-Default fürs Image):

```ini
# /usr/share/sway/config.d/95-noctalia.conf
exec qs -c noctalia-shell
```

> [!warning] Vor dem Image offene Entscheidungen
> - **Supply-Chain:** Terra (Drittanbieter, upstream-gesegnet, beide Arches) akzeptieren – oder `noctalia-qs` selbst bauen?
> - **Track:** bewusst auf **v4** (`-legacy`, `qs`-Binary) bleiben – oder gleich **v5** (beta) evaluieren? v5 würde den Runner-/Binary-Namen erneut verschieben (bereits für die v5-Migration vorgemerkt).

## Aufgaben

- [ ] Terra-Repo platzieren + `terra-release noctalia-shell` layern, Reboot
- [ ] `rpm -q noctalia-shell` – Version prüfen (muss **v4.7.x** sein)
- [ ] `qs -c noctalia-shell` manuell in Sway-Session starten (ohne Config-Änderung)
- [ ] Sway-Workspace-Indikator live gegenchecken (Anzeige + Klick-Wechsel)
- [ ] Settings-Panel durchgehen, `~/.config/noctalia/settings.json` sichten
- [ ] Theming-Env (`QT_QPA_PLATFORMTHEME=gtk3` + `nwg-look`) testen
- [ ] Wegwerf-Layer wieder entfernen (`uninstall` + Repo-Datei löschen), Reboot
- [ ] Erkenntnisse ins Containerfile übertragen (`COPY terra.repo` + `dnf install`)
- [ ] Entscheidung Supply-Chain (Terra vs. Eigenbau) und Track (v4 vs. v5)

## Verwandte Notizen

- [[09-yoga-buildumgebung]]
- [[05-hidpi-und-monitore]]
- [[02-nushell-konfigurieren]]  <!-- geplant, ggf. Dateinamen anpassen -->
- [[Office-Paket für Hyprland – Vergleich & LibreOffice-Installation]]  <!-- ggf. Dateinamen anpassen -->
