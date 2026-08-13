---
titel: Noctalia per rpm-ostree-Layering — Installation, Start, Rückbau
teil_von: "[[Noctarow]]"
tags: [noctarow, noctalia, rpm-ostree, layering, waybar, bash, exploration]
zielgeraet: Fedora Atomic (Sway bzw. Hyprland)
erstellt: 2026-08-02
status: entwurf
---

# Noctalia per rpm-ostree-Layering — Installation, Start, Rückbau

> [!info] Zweck und Abgrenzung
> Dieser Leitfaden beschreibt den **Explorationsweg**: Noctalia schnell auf ein
> laufendes Atomic-System legen, ansehen, rückstandsfrei wieder abbauen. Der
> **Zielweg** bleibt der Containerfile-Build — siehe
> [[docs/09-yoga-buildumgebung]]. Gelayerte Pakete verlangsamen jedes
> `bootc upgrade` und verschwinden beim Switch auf das Container-Image ohnehin.

> [!warning] Status `entwurf`
> Die Befehle sind **nicht** end-to-end live verifiziert. Insbesondere die
> `include`-Reihenfolge der Sway-Drop-ins (Schritt 3) ist offen und muss auf
> dem Zielsystem geprüft werden, bevor diese Note auf `verifiziert_am`
> hochgestuft wird.

Alle Befehle in **bash**.

---

## Schritt 0 — Ausgangslage festhalten

```bash
rpm-ostree status | head -n 12
bootc status
```

Notiere, was **vorher** unter `LayeredPackages:` steht. Ohne diesen Bezugspunkt
kannst du am Ende nicht belegen, dass der Rückbau vollständig war.

---

## Schritt 1 — Terra-Repo einrichten

Noctalia kommt nicht aus den Fedora-Repos, sondern von Fyra Labs.

```bash
sudo tee /etc/yum.repos.d/terra.repo > /dev/null <<'EOF'
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
EOF
```

Das Heredoc ist **quotiert** (`<<'EOF'`) — sonst würde bash `$releasever`
expandieren und dnf bekäme eine leere URL.

`/etc` ist auf ostree schreibbar; das gilt weiterhin, im Gegensatz zu `/usr`.

Kontrolle:

```bash
cat /etc/yum.repos.d/terra.repo
```

---

## Schritt 2 — Installieren

```bash
sudo rpm-ostree install --apply-live noctalia-shell
```

`--apply-live` legt das Paket zusätzlich in den **laufenden** Baum — du sparst
den Reboot. Ohne das Flag ist ein `systemctl reboot` nötig, bevor das Binary da
ist.

> [!warning] Exit-Code 0 ist kein Beweis
> Ein `Obsoletes` in Terra kann eine Anfrage stillschweigend umleiten (das
> `terra-obsolete`-Muster, siehe [[docs/01-erkenntnisse]]). Immer gegenprüfen:

```bash
rpm -q noctalia-shell noctalia-qs
```

Kommt hier etwas anderes zurück als erwartet: **abbrechen**, nicht
weitermachen.

> [!caution] `quickshell` nicht zusätzlich installieren
> `noctalia-qs` liefert dieselben Provides und kollidiert. Das korrigiert die
> ältere Annahme aus [[docs/07-referenz-quellen]].

---

## Schritt 3 — waybar abschalten

### 3a — Erst feststellen, wer waybar startet

```bash
# Sway
grep -ls waybar /usr/share/sway/config.d/*.conf /etc/sway/config.d/*.conf 2>/dev/null

# Hyprland
grep -ls waybar /usr/share/hypr/hyprland.conf ~/.config/hypr/hyprland.conf 2>/dev/null
```

> [!important] Es ist waybar, nicht swaybar
> Fedora startet waybar als **eigenständigen Prozess per `exec`**, nicht als
> Sways internen `bar {}`-Block. Deshalb wirkt
> `swaymsg bar mode invisible` **nicht** —
> `swaymsg -t get_bar_config` liefert `[]`.

### 3b — Sofort für die laufende Sitzung

```bash
pkill -x waybar
pgrep -al waybar    # muss leer sein
```

### 3c — Dauerhaft, Hyprland

Die `exec-once`-Zeile in `~/.config/hypr/hyprland.conf` entfernen oder
auskommentieren. Vorher sichern:

```bash
cp ~/.config/hypr/hyprland.conf ~/.config/hypr/hyprland.conf.bak-$(date +%Y%m%d)
sed -i 's/^\(\s*exec-once\s*=\s*waybar\)/# \1/' ~/.config/hypr/hyprland.conf
grep -n waybar ~/.config/hypr/hyprland.conf
hyprctl reload
```

Das ist Userland — sauber, sichtbar, jederzeit rückbaubar.

### 3d — Dauerhaft, Sway auf Atomic

Hier liegt der Haken: der Snippet steht in `/usr/share`, und `/usr` ist
read-only. Erst die Include-Kette prüfen:

```bash
grep -E '^[[:space:]]*include' /etc/sway/config
```

Werden **beide** Verzeichnisse eingebunden (`/usr/share/sway/config.d/*` und
`/etc/sway/config.d/*`), dann verdrängt eine gleichnamige leere Datei in `/etc`
den Original-Snippet **nicht** — sie kommt zusätzlich hinzu. Für die
Exploration bleibt dann nur die grobe Variante:

```bash
sudo mkdir -p /etc/sway/config.d
printf 'exec_always --no-startup-id pkill -x waybar\n' \
  | sudo tee /etc/sway/config.d/99-no-waybar.conf > /dev/null
swaymsg reload
```

> [!warning] Bewusst eine Krücke
> `exec_always pkill` ist ein Rennen gegen den `exec`, der waybar startet — in
> der Praxis meist gewonnen, aber nicht garantiert. Der **saubere** Weg ist die
> leere gleichnamige Datei im Image:
> ```
> COPY sway/90-bar.conf /usr/share/sway/config.d/90-bar.conf
> ```
> Siehe [[docs/09-yoga-buildumgebung]]. Diese Krücke gehört nicht in ein
> Image und nicht auf eine Schulungsmaschine.

> [!note] swayidle prüfen
> Auf Sway Atomic startet ein weiteres Drop-in `swayidle`, das mit Noctalias
> Idle-Handling kollidiert. Gleiches Verfahren:
> ```bash
> grep -ls swayidle /usr/share/sway/config.d/*.conf 2>/dev/null
> pkill -x swayidle
> ```

---

## Schritt 4 — Noctalia starten

Erst im Vordergrund, damit du die Fehlermeldungen siehst:

```bash
qs -c noctalia-shell
```

Läuft es, per Compositor starten lassen:

```bash
swaymsg exec 'qs -c noctalia-shell'            # Sway
hyprctl dispatch exec 'qs -c noctalia-shell'   # Hyprland
```

Autostart für die Exploration (Sway):

```bash
printf 'exec qs -c noctalia-shell\n' \
  | sudo tee /etc/sway/config.d/95-noctalia.conf > /dev/null
```

Hyprland: `exec-once = qs -c noctalia-shell` in die User-Config eintragen.

---

## Schritt 5 — Prüfen

```bash
pgrep -a qs          # Noctalia läuft
pgrep -al waybar     # muss leer sein
rpm -q noctalia-shell
rpm-ostree status | head -n 12
```

---

## Schritt 6 — Kompletter Rückbau

Die Reihenfolge zählt: erst Autostart, dann Prozess, dann Paket, dann
Userdaten, dann das alte Deployment.

### 6a — Autostart und waybar-Unterdrückung entfernen

```bash
sudo rm -f /etc/sway/config.d/95-noctalia.conf /etc/sway/config.d/99-no-waybar.conf
```

Bei Hyprland die auskommentierte `exec-once`-Zeile wieder aktivieren oder die
Sicherung zurückspielen.

### 6b — Prozess beenden

```bash
pkill -f 'qs -c noctalia-shell'
```

### 6c — Paket abbauen

```bash
sudo rpm-ostree uninstall noctalia-shell
```

Oder alles auf einmal zurück auf reines Basis-Image — `reset` entfernt
gelayerte Pakete, lokale RPMs, Overrides und initramfs-Argumente in einem Zug:

```bash
sudo rpm-ostree reset
```

> [!important] Was `reset` **nicht** tut
> Es macht kein vorheriges `rpm-ostree rebase` bzw. `bootc switch` rückgängig.
> Das Basis-Image bleibt das, worauf du zuletzt gewechselt hast.

### 6d — Repo-Datei weg, dann neu starten

```bash
sudo rm -f /etc/yum.repos.d/terra.repo
systemctl reboot
```

### 6e — Userdaten (nach dem Reboot)

`/home` ist nicht Teil des Images und überlebt jeden Rollback. Bleiben diese
Verzeichnisse liegen, testest du später nicht das Image, sondern
*Image + Altlasten*.

```bash
for d in ~/.config/noctalia ~/.cache/noctalia ~/.local/state/noctalia \
         ~/.config/quickshell ~/.cache/quickshell; do
  if [ -e "$d" ]; then
    rm -rf "$d"
    echo "entfernt: $d"
  fi
done
```

Ebenso prüfen, ob eine User-Konfiguration liegen geblieben ist — eine eigene
`~/.config/sway/config` überschattet die **komplette** System-Default:

```bash
ls -d ~/.config/sway/config ~/.config/sway/config.d 2>/dev/null
```

### 6f — Altes Deployment entfernen

Sonst bootest du im Ernstfall versehentlich zurück in die Exploration.

```bash
sudo rpm-ostree cleanup -r
sudo rpm-ostree cleanup -b -m -p
rpm-ostree status
```

Sauber heißt: kein `LayeredPackages`, kein `LocalPackages`, kein
`ReplacedBasePackages`, genau ein Deployment mit `●`.

> [!note] waybar kommt von selbst zurück
> Der Original-Snippet in `/usr/share` wurde nie angefasst — mit dem Entfernen
> von `99-no-waybar.conf` startet waybar wieder. Bei Hyprland musst du die
> `exec-once`-Zeile manuell wiederherstellen.

---

## Weitere Rückwege im Überblick

| Weg | Wirkung |
|---|---|
| `sudo rpm-ostree uninstall <paket>` | ein Layer weg, neues Deployment |
| `sudo rpm-ostree reset` | alle Layer, lokale RPMs, Overrides, kargs weg |
| `sudo rpm-ostree rollback` | vorheriges Deployment booten (nur eins zurück) |
| GRUB-Menü, älteres Deployment | einmalig, verändert nichts dauerhaft |
| `sudo bootc rollback` | Rückweg nach `bootc switch`, wenn Image-verwaltet |

---

## Prüfliste

```bash
rpm-ostree status | head -n 12
rpm -q noctalia-shell        # nach Rückbau: "not installed"
pgrep -al waybar             # nach Rückbau: läuft wieder
pgrep -a qs                  # nach Rückbau: leer
ls /etc/yum.repos.d/
ls -d ~/.config/noctalia ~/.cache/noctalia 2>/dev/null
```

## Aufgaben

- [ ] `include`-Reihenfolge in `/etc/sway/config` live prüfen (Schritt 3d)
- [ ] Verhalten von `--apply-live` mit Qt-Abhängigkeiten verifizieren
- [ ] swayidle-Drop-in-Dateinamen live bestätigen
- [ ] Nach vollständigem Durchlauf: Status auf `verifiziert_am` hochstufen

## Verwandte Notizen

- [[docs/01-erkenntnisse]]
- [[docs/07-referenz-quellen]]
- [[docs/09-yoga-buildumgebung]]
