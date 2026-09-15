---
titel: Autostart unter Sway — warum der Haken im Nextcloud-Client nichts bewirkt
teil_von: "[[README]]"
tags: [sway, autostart, systemd, xdg, nextcloud, flatpak, portal, bootc, nushell]
zielgeraet: Fedora Sway Atomic (x86_64), Lenovo Yoga 920
erstellt: 2026-08-13
status: entwurf
verifiziert_gegen: —
---

# 18 — Autostart unter Sway

Symptom: Im Nextcloud-Client ist „Beim Systemstart ausführen" aktiviert, nach
dem Hochfahren läuft der Client trotzdem nicht.

> [!warning] Status: Entwurf
> Die Ursachenanalyse ist plausibel und gegen die Sway-/systemd-Dokumentation
> belegt, aber auf dem Zielgerät **nicht gemessen**. Erst nach einem
> Kaltstart mit erfolgreichem Start auf `verifiziert` heben und
> `verifiziert_am` eintragen.

## Kernaussage

**Sway implementiert XDG-Autostart nicht.** Der Haken im Client schreibt eine
`.desktop`-Datei nach `~/.config/autostart/` — auf GNOME oder KDE liest die
jemand aus, unter Sway niemand. Der Schalter ist korrekt gesetzt; es fehlt
der Konsument auf der Empfängerseite. Kein Fehler im Client, kein Fehler in
der Konfiguration, sondern eine fehlende Komponente.

Das reiht sich in ein bekanntes Muster dieses Projekts ein: Sway liest auch
`localectl` nicht ([[docs/01-erkenntnisse]]). Was Desktop-Umgebungen als
selbstverständlich mitbringen, ist bei einem reinen Compositor eine bewusst
zu treffende Entscheidung.

## Zwei Fehlerbilder

| | Fall A | Fall B |
|---|---|---|
| Installationsart | RPM aus dem Image | Flatpak |
| Mechanismus des Schalters | `.desktop` nach `~/.config/autostart/` | Background-Portal (`org.freedesktop.portal.Background`) |
| Beobachtung | Datei **ist** da, niemand liest sie | Datei fehlt trotz gesetztem Haken |
| Ursache | kein XDG-Autostart-Konsument in der Session | kein Portal-Backend bietet die Schnittstelle an |

Diagnose Nr. 1 unten entscheidet die Richtung.

## Diagnose

```nu
# 1 — Wurde überhaupt eine Autostart-Datei geschrieben?
ls ~/.config/autostart | select name size modified
```

```nu
# 2 — Falls ja: Exec-Zeile, OnlyShowIn/NotShowIn
open --raw ~/.config/autostart/com.nextcloud.desktopclient.nextcloud.desktop
```

```nu
# 3 — RPM aus dem Image oder Flatpak?
rpm -q nextcloud-client
flatpak list --columns=application,origin | find -i nextcloud
```

```nu
# 4 — Wie meldet sich die Session, existiert das Sway-Session-Target?
$env.XDG_CURRENT_DESKTOP?
systemctl --user list-unit-files | find sway-session
ls /usr/share/sway/config.d/ | select name
ls /etc/sway/config.d/ | select name
```

```nu
# 5 — Nur bei Flatpak relevant: bietet ein Backend das Background-Portal an?
busctl --user introspect org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop
| find -i background
```

> [!note] `OnlyShowIn` ist ein stiller Killer
> Steht in der `.desktop`-Datei `OnlyShowIn=GNOME;` oder `NotShowIn=sway;`,
> überspringt selbst ein vorhandener Konsument den Eintrag. Diagnose Nr. 2
> nicht überspringen, auch wenn die Datei existiert.

## Lösung: eigene systemd-User-Unit

Nicht das Autostart-Verzeichnis reparieren, sondern umgehen. Eine User-Unit
gibt Protokoll, Neustart nach Absturz und eine saubere Bindung an die
Session — ein `exec`-Eintrag in der Sway-Config gibt nichts davon.

```nu
let heim = (if "home-path" in ($nu | columns) { $nu.home-path } else { $nu.home-dir })
let unit = ($heim | path join ".config/systemd/user/nextcloud-client.service")
mkdir ($unit | path dirname)
```

> [!tip] Das `home-path`/`home-dir`-Problem
> 0.114 hat `$nu.home-path` in `home-dir` umbenannt; `nu-check` fängt das
> nicht ab. Die Fallunterscheidung oben läuft auf beiden Versionen.

Exec-Zeile nach Installationsart — verlässliche Quelle ist Diagnose Nr. 2:

```nu
let start = "/usr/bin/nextcloud --background"
# Flatpak stattdessen:
# let start = "/usr/bin/flatpak run com.nextcloud.desktopclient.nextcloud --background"

$"[Unit]
Description=Nextcloud Desktop Client
PartOf=graphical-session.target
After=graphical-session.target

[Service]
Type=simple
ExecStart=($start)
Restart=on-failure
RestartSec=5

[Install]
WantedBy=sway-session.target
" | save --force $unit
```

```nu
systemctl --user daemon-reload
systemctl --user enable --now nextcloud-client.service
systemctl --user status nextcloud-client.service
```

Nach dem nächsten Neustart gegenlesen:

```nu
journalctl --user -b -u nextcloud-client.service --no-pager | lines | last 40
```

> [!important] `sway-session.target` prüfen, nicht annehmen
> Ist Diagnose Nr. 4 an dieser Stelle leer, existiert das Target nicht und
> `enable` legt eine wirkungslose Verknüpfung an. `graphical-session.target`
> ist **kein** Ersatz — es darf nicht direkt aktiviert werden, es wird von
> der Session gezogen. Dann zuerst klären, welche systemd-Anbindung
> `/usr/share/sway/config.d/` mitbringt.

## Alternative: XDG-Autostart nachrüsten

systemd bringt einen Generator mit, der `~/.config/autostart/*.desktop` in
Units übersetzt. Er muss nur ausgelöst werden — Drop-in nach
`60-autostart.conf`:

```
exec systemctl --user start xdg-desktop-autostart.target
```

Ergebnis prüfen:

```nu
systemctl --user list-units "app-*" --all | lines | find -i nextcloud
```

Das ist die generische Variante — sie startet **alles**, was je in
`~/.config/autostart/` gelandet ist. Für eine Flotte, bei der kontrolliert
sein soll, was hochkommt, ist die dedizierte Unit vorzuziehen. Für einen
einzelnen Arbeitsplatz mit vielen GUI-Anwendungen ist der Generator der
geringere Pflegeaufwand.

## Fallstricke, die als „startet nicht" erscheinen

**Kein Tray-Host.** Der Client startet mit `--background` ohne Fenster. Hat
Noctalias Bar noch keinen StatusNotifierItem-Host oben, wenn der Client sich
registrieren will, ist nichts zu sehen — der Prozess läuft trotzdem. Messen
statt urteilen:

```nu
ps | where name =~ nextcloud | select pid name start
```

**Kein entsperrter Schlüsselbund.** Der Client holt das Passwort über
libsecret. Läuft kein `gnome-keyring-daemon`, hängt er in einer
Passwortabfrage oder bleibt unverbunden:

```nu
ps | where name =~ "gnome-keyring|kwalletd" | select pid name
```

**Startreihenfolge.** `After=graphical-session.target` garantiert nicht, dass
Bar und Portal bereits fertig sind. Zeigt sich das als Race, ist
`ExecStartPre=/usr/bin/sleep 3` eine Krücke, keine Lösung — sauberer ist eine
Abhängigkeit auf die Unit, die Noctalia startet.

## Reproduzierbarkeit: ins Image, nicht ins Home

`~/.config/systemd/user/` liegt auf Atomic unter `/var`, ist damit
maschinenlokal und übersteht zwar `bootc upgrade`, wandert aber nicht ins
Image. Für die Flotte gehört die Unit ins Containerfile — Build-Kontext
ausschließlich bash:

```dockerfile
COPY nextcloud-client.service /usr/lib/systemd/user/nextcloud-client.service
RUN mkdir -p /usr/lib/systemd/user/sway-session.target.wants \
    && ln -sf ../nextcloud-client.service \
       /usr/lib/systemd/user/sway-session.target.wants/nextcloud-client.service
```

> [!caution] Kein `systemctl enable` nach `--apply-live`
> Das schreibt Symlinks nach `/etc/systemd/system/`, die nach `bootc switch`
> ins Leere zeigen (siehe [[docs/01-erkenntnisse]]). Der Symlink gehört per
> `ln -sf` ins Containerfile, nicht per `enable` auf das laufende System.

Der Sway-Drop-in aus dem Alternativweg gehört analog nach
`/usr/share/sway/config.d/60-autostart.conf`, nicht nach `/etc/` — `/etc`
bleibt für lokale Übersteuerungen frei.

## Compositor-Neutralität

Für die Sway-vs-Hyprland-Abwägung (Notiz im Coaching-Vault, nicht in diesem Repo) relevant: Hyprland implementiert XDG-Autostart
ebenfalls nicht; dort ist `exec-once` das native Mittel. Der **User-Unit-Weg
ist der einzige, der beide Compositor abdeckt** — es ändert sich nur der
Zielname im `WantedBy`. Das spricht dafür, Autostart in `policy.nuon` als
Datenzeile zu führen und das Target beim Rendern einzusetzen, statt
`exec`-Zeilen in Compositor-Configs zu pflegen.

## Offene Punkte

- [ ] Diagnose Nr. 1–5 auf dem Yoga 920 durchlaufen, Fall A gegen B entscheiden
- [x] Existiert `sway-session.target` im Basis-Image? — **ja**, gegengeprüft
      am 2026-09-15 gegen `localhost/noctarow:44`. Vorhanden sind
      `sway-session.target`, `sway-session-shutdown.target` und
      `sway-xdg-autostart.target` unter `/usr/lib/systemd/user/`. Damit ist
      `WantedBy=sway-session.target` der belegbare Weg.
- [ ] Kaltstart-Test: läuft der Client, bevor die Bar oben ist? → Race prüfen
- [ ] Tray-Registrierung gegen Noctalias StatusNotifierItem-Host messen
- [ ] Schlüsselbund: welcher Daemon läuft im Sway-Atomic-Image überhaupt?
- [ ] Entscheidung dedizierte Unit vs. `xdg-desktop-autostart.target` festhalten
- [ ] Nach Entscheidung: Unit + Symlink ins Containerfile promoten
- [ ] Autostart-Einträge als Feld in `policy.nuon` vorsehen
- [ ] Zusammenspiel mit der Dateifreigabe Host/Gast (KVM-Notiz im Coaching-Vault, nicht in diesem Repo): der Host-Client
      muss laufen, sonst schreibt der Windows-Gast in einen toten Baum

## Kernaussagen in vier Sätzen

Sway hat keinen XDG-Autostart-Konsumenten — der Haken im Client ist gesetzt,
liest ihn aber niemand. Eine systemd-User-Unit mit
`WantedBy=sway-session.target` ist der bessere Weg als der `exec`-Eintrag,
weil sie Protokoll, Neustartverhalten und eine prüfbare Bindung mitbringt.
Bei Flatpak-Installationen läuft der Schalter stattdessen über das
Background-Portal und scheitert still, wenn kein Backend die Schnittstelle
anbietet. Alles, was dauerhaft gelten soll, gehört nach
`/usr/lib/systemd/user/` im Containerfile — `~/.config/systemd/user/` ist
maschinenlokal und für die Flotte wertlos.
