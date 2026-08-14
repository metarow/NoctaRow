---
titel: Flatpak auf Fedora Sway Atomic — GUI-Frontends, User- vs. System-Kontext, bootc-Konsequenz
aliases: [Flatpak-GUI, Bazaar-User-Modus, Flathub-Remote, var-lib-flatpak]
teil_von: "[[README]]"
tags: [flatpak, flathub, bazaar, warehouse, sway, atomic, bootc, nushell, xdg]
erstellt: 2026-08-13
system: Fedora Sway Atomic 44 (allgemein); User-Modus-Betrachtung für Lenovo Yoga 920
verifiziert_gegen: keine (Recherche + Herleitung; Live-Test steht aus)
status: entwurf
---

# 19 — Flatpak auf Sway Atomic

Klärung dreier zusammenhängender Fragen: Läuft Flatpak auf dem Base-Image
schon out of the box, gibt es dafür eine grafische Oberfläche, und wohin
schreibt ein `--system`-Install eigentlich. Der letzte Punkt entscheidet,
warum Flatpak-Apps **nicht** ins Containerfile gehören.

> [!info] Statuslegende dieser Notiz
> - **✅ dokumentiert** — allgemein belegte Flatpak-/OSTree-Semantik
> - **🟡 hergeleitet** — aus dem eigenen Setup gefolgert, plausibel, aber
>   noch nicht auf Yoga/Image live gemessen
> - **⬜ offen** — Messung bzw. Entscheidung steht aus

---

## 1 — Flatpak ist da, Flathub nicht ✅

Flatpak ist auf allen Fedora Atomic Desktops (auch Sway Atomic)
vorinstalliert und dort der **vorgesehene** Weg für GUI-Apps — gerade weil
`rpm-ostree install` den `bootc upgrade`-Pfad bricht (siehe
[[01-erkenntnisse]]). Vorhanden ist das `flatpak`-Binary und meist die
Fedora-eigene Remote (`registry.fedoraproject.org`). Was fehlt, ist
**Flathub** — selbst hinzufügen:

```nu
flatpak remote-add --if-not-exists --system flathub https://dl.flathub.org/repo/flathub.flatpakrepo
```

Bestand prüfen:

```nu
which flatpak
flatpak remotes
```

---

## 2 — GUI-Frontends ✅ / 🟡

Sway Atomic bringt **keine** GNOME Software / Plasma Discover mit. Diese
nachzulayern würde den `bootc upgrade`-Pfad brechen. Regel deshalb: eine
GUI wählen, die **selbst ein Flatpak** ist — dann bleibt sie sauber
außerhalb des Images.

| App | Zweck | App-ID |
|---|---|---|
| **Bazaar** | App-Store (Default auf Bluefin/Bazzite/Aurora) | `io.github.kolunmi.Bazaar` |
| **Warehouse** | Verwaltung: Berechtigungen, Daten, Aufräumen, Batch | `io.github.flattool.Warehouse` |
| **Flatseal** | reiner Berechtigungs-Editor (Sandbox-Overrides pro App) | `com.github.tchx84.Flatseal` |

```nu
flatpak install --system flathub io.github.kolunmi.Bazaar
flatpak install --system flathub io.github.flattool.Warehouse
flatpak install --system flathub com.github.tchx84.Flatseal
```

> [!warning] Theming-Vorbehalt 🟡
> Alle drei sind GTK/GNOME-gestylt. Unter unserem qt6ct/Kvantum-Setup
> greift das Theming nicht wie bei den Qt-Tools; Bazaar wirkt außerhalb von
> GNOME optisch fehl am Platz. Wayland-nativ (GTK) sind sie aber, und
> funktional stört es nicht.

Für den reinen Store-Zweck reicht Bazaar; **Warehouse** ist die bessere
Ergänzung fürs Aufräumen und — anders als Bazaar — unkritisch beim
Kontext-Filtern (siehe Abschnitt 4).

---

## 3 — Wohin Flatpaks installiert werden ✅

Zwei getrennte Kontexte mit getrennten Zielverzeichnissen:

| Kontext | Installationsziel | Rechte |
|---|---|---|
| `--system` | `/var/lib/flatpak` | root / polkit |
| `--user` | `~/.local/share/flatpak` | keine, kein Auth-Agent nötig |

Struktur unter `/var/lib/flatpak`:

| Pfad | Inhalt |
|---|---|
| `repo/` | OSTree-Repo, die eigentlichen Objekte |
| `app/<id>/<arch>/<branch>/active` | Deploy der App (Hardlinks ins Repo) |
| `runtime/…` | Runtimes (Platform, GL-Extensions) |
| `exports/share` | `.desktop`, Icons, D-Bus-Services → von `XDG_DATA_DIRS` eingesammelt |
| (Remotes systemweit) | `/etc/flatpak/remotes.d/` |

Nachsehen:

```nu
ls /var/lib/flatpak
flatpak list --system --columns=application,installation,size
```

> [!note] App-Daten liegen immer im Home ✅
> Auch bei `--system`-Apps landen Konfiguration und User-Daten pro User
> unter `~/.var/app/<app-id>/`, User-seitige Berechtigungs-Overrides unter
> `~/.local/share/flatpak/overrides`. Die **Installation** ist systemweit,
> der **State** nicht.

---

## 4 — Bazaar im reinen User-Modus 🟡 / ⬜

Frage: Läuft Bazaar, wenn Flathub nur `--user` existiert? Grundsätzlich ja —
mit zwei Fallstricken, die genau in unserem Setup greifen.

**Kontext muss übereinstimmen:** Liegt Flathub nur `--user` vor, muss auch
Bazaar `--user` installiert werden, sonst findet die System-Installation die
Remote nicht.

```nu
flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user flathub io.github.kolunmi.Bazaar
flatpak run io.github.kolunmi.Bazaar
```

`--user` braucht weder root noch polkit — das ist der Grund, weshalb es ohne
Auth-Agent durchläuft.

### 4.1 Launcher-Eintrag fehlt unter Nushell 🟡

`/etc/profile.d/flatpak.sh` hängt `~/.local/share/flatpak/exports/share` an
`XDG_DATA_DIRS` an — Nushell sourced das nicht (bekanntes Muster aus der
WSLg-Runde, siehe Notiz 15). Aus einer Nushell-Login-Shell gestartet, taucht
Bazaar in keinem Menü auf; `flatpak run` geht trotzdem. Prüfen:

```nu
$env.XDG_DATA_DIRS | split row ':' | find flatpak
```

Kommt nichts zurück, in `env.nu` ergänzen:

```nu
$env.XDG_DATA_DIRS = ([
    $env.XDG_DATA_DIRS?
    $"($nu.home-path)/.local/share/flatpak/exports/share"
    "/var/lib/flatpak/exports/share"
] | compact | str join ":")
```

Über SDDM gestartet ist das meist schon gesetzt → erst prüfen, dann anfassen.

### 4.2 Bazaar zielt evtl. trotzdem auf System ⬜

> [!warning] Ungeklärt, vor Ort zu testen
> Aus dem Bluefin-Umfeld gibt es Berichte, dass die Flatpak-Variante von
> Bazaar bereits vorhandene User-Flatpaks nicht listet und keine Wahl
> zwischen System- und User-Kontext bietet, sondern stets systemweit
> installiert. Ob das in der aktuellen Version noch gilt, ist offen. Bei uns
> würde ein System-Install mangels System-Flathub-Remote schlicht scheitern.
>
> **Test (30 s):** Bazaar öffnen → Tab **Installed**. Erscheint der
> `--user`-Bestand, ist alles gut. Bleibt die Liste leer, ist Bazaar für den
> reinen User-Modus der falsche Kandidat.

**Warehouse** ist hier unkritisch — es filtert und zeigt User- und
System-Kontext explizit:

```nu
flatpak install --user flathub io.github.flattool.Warehouse
```

---

## 5 — Konsequenz für das Noctarow-Image ✅

`/var/lib/flatpak` liegt in `/var`, und `/var` wird bei bootc **nicht** aus
dem Image-Content befüllt — es ist maschinenlokaler State, der über
`bootc upgrade` hinweg unverändert bleibt. Ein `flatpak install --system` im
Containerfile schreibt also ins Nirwana.

Reproduzierbar im Image ist nur die **Remote-Definition**, nicht die Apps:

```dockerfile
# im Containerfile — nur die Remote, nicht die App
COPY flatpak/flathub.flatpakrepo /etc/flatpak/remotes.d/flathub.flatpakrepo
```

Die Apps kommen per **First-Boot-systemd-Unit** (analog zum bestehenden
`homebrew-bootstrap.service`-Muster), die eine idempotente Nushell-Applist
abarbeitet. Das ist der Produktionspfad fürs Image.

Der reine **User-Modus** (Abschnitt 4) ist dagegen die Wahl fürs persönliche
Yoga-Setup — er ist nicht Teil des reproduzierbaren Images.

---

## Offene Punkte

- [ ] ⬜ Bazaar-Kontext-Verhalten auf dem Yoga live prüfen (Abschnitt 4.2)
- [ ] ⬜ `XDG_DATA_DIRS`-Ergänzung unter SDDM-Session gegenmessen — ist der
      Flatpak-Export-Pfad dort bereits gesetzt? (Abschnitt 4.1)
- [ ] ⬜ First-Boot-Unit + Nushell-Applist ausformulieren und testen, bevor
      sie hier als verifiziert einzieht (Abschnitt 5)
- [ ] ⬜ Entscheiden: Bazaar oder Warehouse (oder beide) als Default in die
      Applist — abhängig vom Ausgang des Kontext-Tests

## Verwandte Notizen

- [[01-erkenntnisse]] — warum `rpm-ostree install` den bootc-Pfad bricht
- [[02-umgebung-wsl]] — Nushell-Umgebung, `env.nu`
- [[08-verteilung]] — was auf Windows, was in WSL liegt
- Notiz 15 — Flatpak/Nushell-`XDG_DATA_DIRS`-Muster (WSLg)
