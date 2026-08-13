---
tags:
  - fedora
  - nushell
  - installation
  - hyprland-setup
erstellt: 2026-06-28
status: aktiv
---

# Nushell installieren

> [!info] Kontext
> Erster Schritt der Fedora-Einrichtung mit Hyprland und Nushell. Nushell (`nu`) ist eine in Rust geschriebene Shell, die Befehlsausgaben als **strukturierte Daten** (Tabellen, Records) behandelt statt als reinen Text.

> [!warning] Bootstrapping-Hinweis
> Die Installationsbefehle in **Methode 1–3** werden in deiner *aktuellen* Shell (bash) ausgeführt, weil Nushell ja noch nicht existiert. `dnf` ist ein externes Programm und verhält sich in jeder Shell gleich. Ab dem Abschnitt **Verifizieren** befindest du dich in `nu`, dort gilt native Nushell-Syntax.

---

## Methode 1 – Fedora-Repo (einfachste Variante)

Nushell ist in den offiziellen Fedora-Repos enthalten. Das Paket heißt `nu` (nicht `nushell`):

```sh
sudo dnf --refresh install nu
```

> [!note] Versionshinweis
> Nushell veröffentlicht etwa alle 4 Wochen ein Release, oft mit Breaking Changes. Die Version im Fedora-Repo kann daher hinterherhinken. Wenn du der aktuellen Nushell-Doku 1:1 folgen willst, nutze **Methode 2** oder **3**.

---

## Methode 2 – COPR `atim/nushell` (aktueller)

Gut gepflegtes Community-Repo, das den Releases eng folgt. Paketname hier: `nushell`.

```sh
sudo dnf copr enable atim/nushell -y
sudo dnf install nushell -y
```

---

## Methode 3 – Offizielles Gemfury-Repo (neueste Version, vom Nushell-Team)

```sh
echo '[gemfury-nushell]
name=Gemfury Nushell Repo
baseurl=https://yum.fury.io/nushell/
enabled=1
gpgcheck=0
gpgkey=https://yum.fury.io/nushell/gpg.key' | sudo tee /etc/yum.repos.d/fury-nushell.repo

sudo dnf install -y nushell
```

> [!caution] Nur **eine** Quelle aktivieren
> Aktiviere nicht gleichzeitig Fedora-Repo, COPR und Gemfury für Nushell – das kann zu Paketkonflikten beim Update führen. Entscheide dich für einen Weg.

---

## Verifizieren

Ab hier kannst du `nu` starten – einfach `nu` eintippen. Schnelltest noch aus bash:

```sh
nu --version
```

Innerhalb von Nushell (native Syntax) liefert `version` einen **Record** statt nur einer Zeile:

```nu
version
```

```nu
# Einzelnes Feld auslesen
version | get version
```

---

## Konfigurationsdateien

Nushell legt die Konfiguration unter `~/.config/nushell/` an. Die Pfade fragst du direkt ab der Shell ab:

```nu
$nu.config-path    # ~/.config/nushell/config.nu
$nu.env-path       # ~/.config/nushell/env.nu
$nu.history-path
```

Dateien direkt im Editor öffnen:

```nu
config nu     # öffnet config.nu
config env    # öffnet env.nu
```

> [!tip] Leere Config ist normal
> In aktuellen Versionen (ab ~0.100) liegt die Default-Konfiguration eingebaut vor. `config.nu` und `env.nu` enthalten daher nur noch *deine Anpassungen* und dürfen anfangs (fast) leer sein.

---

## Als Standard-Shell setzen

> [!warning] Nushell ist **nicht** POSIX-konform
> `nu` als Login-Shell via `chsh` kann Tools/Skripte stören, die eine POSIX-Shell erwarten (manche Session-/Display-Manager-Skripte, Build-Tools etc.). Für ein Hyprland-Setup ist meist der Terminal-Emulator-Weg sauberer.

### Empfohlen (Hyprland): Nushell im Terminal-Emulator starten

Login-Shell bleibt bash, dein Terminal startet aber direkt `nu`. Beispiel für **Kitty** (`~/.config/kitty/kitty.conf`):

```sh
shell /usr/bin/nu
```

Foot (`~/.config/foot/foot.ini`):

```sh
[main]
shell=/usr/bin/nu
```

> [!note] Diese Terminal-Configs gehören thematisch in die jeweilige Terminal-Notiz – siehe [[Terminal-Emulator einrichten]].

### Alternative: Login-Shell via `chsh`

Erst den Binary-Pfad ermitteln (native Nushell-Syntax):

```nu
which nu
```

`nu` zu den erlaubten Login-Shells hinzufügen (aus bash, da `sudo tee` benötigt wird):

```sh
echo "/usr/bin/nu" | sudo tee -a /etc/shells
```

Standard-Shell setzen:

```sh
chsh -s /usr/bin/nu
```

Prüfen, ob `/usr/bin/nu` eingetragen ist – aus Nushell:

```nu
open /etc/shells | lines | where $it =~ "nu"
```

---

## Nächste Schritte

- [[02-nushell-konfigurieren]] – `config.nu`, `env.nu`, Aliase, Prompt
- [[Terminal-Emulator einrichten]]
- [[Hyprland installieren]]

---

## Befehls-Spickzettel

| Zweck | Befehl | Kontext |
|---|---|---|
| Installieren (Fedora) | `sudo dnf --refresh install nu` | bash |
| Installieren (COPR) | `sudo dnf copr enable atim/nushell -y` | bash |
| Version | `version` | nu |
| Config öffnen | `config nu` | nu |
| Config-Pfad | `$nu.config-path` | nu |
| Binary finden | `which nu` | nu |
| Shells prüfen | `open /etc/shells \| lines` | nu |
