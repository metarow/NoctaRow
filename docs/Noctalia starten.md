---
titel: Noctalia starten
tags:
  - noctalia
  - quickshell
  - hyprland
  - fedora
  - autostart
  - keybinds
erstellt: 2026-07-06
system: Fedora 44 · Hyprland (Lua) · x86_64
status: aktiv
kontext: Hyprland-Vorläufer — Noctarow setzt auf Sway, die IPC-Befehle unten (qs -c, Runner-Namenskopplung) bleiben compositor-unabhängig gültig
---

> [!warning] Kontext: Hyprland-Vorläufer
> Diese Notiz stammt aus der Zeit vor der Sway-Entscheidung für Noctarow. Der
> Systemangaben-Tag „Hyprland" ist **kein** Hinweis auf den Noctarow-Zielweg
> (siehe [[docs/01-erkenntnisse]] und [[docs/16-erkenntnisse-noctalia-container]]
> für den aktuellen Sway-Stand). Die hier beschriebenen Quickshell-IPC-Befehle
> und die Runner-Namenskopplung sind compositor-unabhängig und bleiben gültig.

# Noctalia starten

Noctalia ist **keine eigenständige Binary**, sondern eine Quickshell-Config. Der Start erfolgt immer über den Quickshell-Runner mit dem Config-Namen `noctalia-shell`, den der Runner über `-c` auflöst.

> [!info] Kernaussage
> `noctalia-shell` ist kein Kommando. Ein blanker Aufruf endet mit *„Command `noctalia-shell` not found"*.
> Gestartet wird über den Runner: `qs -c noctalia-shell`.

## Der richtige Startbefehl

```nu
qs -c noctalia-shell
```

Ein sauberer Start meldet im Log u. a. `Noctalia Hello!` und `Configuration Loaded` und läuft dann im Vordergrund weiter (mit `Strg-C` beendbar).

> [!warning] Runner-Name ist an den Paket-Track gekoppelt
> Der Binärname des Runners hängt von der installierten Paket-Variante ab und ist **keine Konstante**:
> - **v4-Track (`-legacy`):** Runner heißt `qs` → `qs -c noctalia-shell`
> - **v5-Track:** Runner kann `noctalia-qs` heißen → `noctalia-qs -c noctalia-shell`
>
> Diese Zuordnung ist eine **Schlussfolgerung** aus den Repo-Signalen (v5 in Beta, upstream-Repo `legacy-v4-plugins`, installierte Version 4.7.7) — nicht schwarz auf weiß aus der Paketbeschreibung bestätigt. Vor jeder Config-Änderung den tatsächlichen Runner prüfen (siehe unten).

## Diagnose: welcher Runner ist installiert?

```nu
# Welcher Runner liegt im PATH?
which qs noctalia-qs quickshell

# Installierte Noctalia-Pakete auflisten (Track + Version)
rpm -qa | find noctalia

# Welchen Runner liefert das qs-Paket wirklich?
rpm -ql noctalia-qs-legacy | lines | where ($it =~ '/bin/')
```

> [!example] Referenz-Ausgabe (dieses System, 2026-07-06)
> - `which` findet nur `/usr/bin/qs` und `/usr/bin/quickshell` — **kein** `noctalia-qs`
> - Pakete: `noctalia-shell-legacy-4.7.7-2.fc44.noarch`, `noctalia-qs-legacy-0.0.12-5.fc44.x86_64`
> - Der v4-Fork (`noctalia-qs-legacy`) stellt den Runner unter dem Namen `qs` bereit
>
> → Korrekter Runner auf diesem System: **`qs`**

## Config-Pfad

Bei Paketinstallation liegt die Config systemweit unter `/etc/xdg/quickshell/noctalia-shell`. Eine User-Override würde unter `~/.config/quickshell/noctalia-shell` liegen.

```nu
["~/.config/quickshell/noctalia-shell" "/etc/xdg/quickshell/noctalia-shell"]
| each {|p| {pfad: $p, existiert: ($p | path expand | path exists)} }
```

## Autostart in Hyprland

Der Autostart muss **denselben Runner** verwenden wie die Keybinds — sonst laufen die IPC-Aufrufe gegen keine Instanz.

Klassische hyprlang-Referenz (zum Übersetzen in die Lua-Config):

```ini
exec-once = qs -c noctalia-shell
```

> [!warning] Lua-Äquivalent des Autostart prüfen
> `exec-once` ist eine Config-Direktive, kein Dispatcher — das Lua-Äquivalent in deiner `hl`-Modul-API ist **nicht** `hl.dsp.exec_cmd`. Die exakte Funktion (z. B. `hl.exec_once(...)` o. ä.) gegen deine `hyprland.lua`-Bindings verifizieren, bevor du sie als gesetzt behandelst.

## Keybind: Launcher-Toggle

> [!warning] Häufiger Fehler — falsch
> ```lua
> hl.bind(mainMod .. " + D", hl.dsp.exec_cmd("noctalia-shell ipc call launcher toggle"))
> ```
> `noctalia-shell` ist kein Kommando → *„Command not found"*. Es fehlt das `qs -c`-Präfix vor dem Config-Namen.

> [!check] Korrigiert
> ```lua
> hl.bind(mainMod .. " + D", hl.dsp.exec_cmd("qs -c noctalia-shell ipc call launcher toggle"))
> ```
> Der hintere Teil `ipc call launcher toggle` war bereits korrekt — es fehlte nur der Runner davor.

> [!note] `exec_cmd` läuft über `/bin/sh`
> Der Aufruf `qs -c noctalia-shell ipc call launcher toggle` ist reine externe Syntax (kein Nu) und läuft daher problemlos über `/bin/sh`. Sobald ein Keybind **Nu-Ausdrücke** braucht, gehört das in eine externe `.nu`-Datei — inline-Nu funktioniert in Hyprland-Keybinds nicht.

## Weitere IPC-Aufrufe

Muster: `qs -c noctalia-shell ipc call <ziel> <funktion>`

```nu
# Launcher umschalten
qs -c noctalia-shell ipc call launcher toggle

# Sperrbildschirm
qs -c noctalia-shell ipc call lockScreen lock

# Sperren + Suspend (z. B. für swayidle)
qs -c noctalia-shell ipc call sessionMenu lockAndSuspend

# Verfügbare IPC-Ziele/-Funktionen auflisten
qs -c noctalia-shell ipc show
```

## Läuft eine Instanz?

```nu
ps | where name =~ "qs" or name =~ "quickshell"
```

> [!info] Harmlose Log-Warnungen beim ersten Start
> Meldungen wie `plugins.json ... File does not exist` und `will create it` sind normal — Noctalia legt `~/.config/noctalia/plugins.json` beim ersten Start selbst an. Kein Handlungsbedarf.

## Verwandte Notizen

> [!note] Querverweise ggf. an tatsächliche Dateinamen anpassen
> Die folgenden Wikilinks sind aus dem Kontext abgeleitet und können abweichen:
> - [[02-nushell-konfigurieren]]
> - [[Hyprland konfigurieren]]
> - [[Noctalia integrieren]]

## Aufgaben

- [ ] Keybind in `hyprland.lua` auf `qs -c noctalia-shell ipc call launcher toggle` korrigieren
- [ ] Autostart-Eintrag prüfen: nutzt derselbe Runner `qs -c noctalia-shell`?
- [ ] Lua-Funktion für den Autostart (`exec-once`-Äquivalent) gegen die `hl`-Bindings verifizieren
- [ ] Installierten Paket-Track bestätigen (`-legacy` = v4?) via `rpm -qa | find noctalia`
- [ ] Bei späterem Wechsel auf den v5-Track: Runner-Name auf `noctalia-qs` umstellen (Autostart **und** alle IPC-Keybinds)
- [ ] Weitere Keybinds/Scripts auf denselben Runner-Präfix vereinheitlichen
