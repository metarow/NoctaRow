---
titel: Sway — Fenstertitelleiste ausblenden (Border-Direktiven)
aliases: [Titelleiste-aus, default_border, Border-Drop-in, 30-borders]
teil_von: "[[README]]"
tags: [sway, config, border, titelleiste, nushell, drop-in, image]
erstellt: 2026-08-13
zielgeraet: NoctaRow-Image (Sway-Atomic), lokal getestet
verifiziert_gegen: Nushell 0.114.1 (save/mkdir-Semantik), Sway-Border-Doku
status: entwurf
---

# 18 — Sway: Fenstertitelleiste ausblenden

Sway hat **keine** eigene „Titelleiste-aus"-Option. Der Titel hängt am
**Border-Typ** eines Fensters — wer die Leiste loswerden will, ändert den
Border, nicht eine separate Titel-Einstellung. Diese Notiz hält den
Mechanismus, zwei überraschende Sonderfälle und einen Nushell-Stolperstein
beim Anlegen des Drop-ins fest.

> [!info] Statuslegende dieser Notiz
> - **✅ verifiziert** — gegen Nushell 0.114.1 bzw. dokumentierte Sway-Semantik
> - **🟡 hergeleitet** — aus der Doku gefolgert, Wirkung noch nicht live gemessen
> - **⬜ offen** — Messung auf Zielhardware steht aus

---

## 1 — Der Mechanismus: `default_border` 🟡

Zwei Direktiven steuern das Verhalten für neu geöffnete Fenster:

```nu
default_border pixel 2
default_floating_border pixel 2
```

| Wert | Wirkung |
|---|---|
| `normal` (Standard) | Rahmen **mit** Titelleiste |
| `pixel <n>` | Rahmen **ohne** Titelleiste, nur ein `<n>` px dünner Fokus-Strich |
| `none` | weder Rahmen noch Titelleiste |

`pixel 2` ist meist der praktischste Wert: Titelleiste weg, aber eine dünne
farbige Fokus-Markierung bleibt. `none` nimmt auch die noch weg.

---

## 2 — Zwei Sonderfälle, die überraschen ✅

> [!warning] Tabbed/Stacked ignoriert `default_border`
> In `tabbed`- und `stacked`-Layouts wird die Titel-/Tableiste **immer**
> angezeigt — unabhängig von `default_border`. Das ist kein Bug: Die Leiste
> ist die einzige Möglichkeit, zwischen den Tabs zu navigieren.
> `default_border` betrifft nur `splith`/`splitv` und floating.
>
> **Relevanz für NoctaRow:** Die Fenster-Policy setzt `workspace_layout
> tabbed` (siehe Fenster-Policy). Damit greift `default_border` in gekachelten
> Workspaces faktisch nicht — die Tableiste bleibt sichtbar. Das ist gewollt
> (Tab-Navigation), muss aber bewusst mitgedacht werden: „Titelleiste weg" gilt
> hier nur für floating Ausnahmen und `split*`-Container.

> [!note] Nur für neu geöffnete Fenster
> `default_border` greift ab dem nächsten geöffneten Fenster. Bereits offene
> Fenster übernehmen den Typ **nicht** rückwirkend. Optionen:
> - einmal ab-/anmelden, oder
> - pro Fenster gezielt: `border pixel 2` auf das fokussierte Fenster.

---

## 3 — Optional: Rahmen an den Bildschirmkanten ⬜

Bei Single-Window auf einem Output stören oft auch die Rahmen an den
Screen-Kanten. Zwei ergänzende Direktiven:

```nu
hide_edge_borders smart
# oder
smart_borders on
```

Werte für den Yoga-Output (4K/HiDPI) noch nicht gemessen — vor Aufnahme ins
Image auf der Zielhardware prüfen.

---

## 4 — Nushell-Stolperstein: `save` legt keine Verzeichnisse an ✅

Beim Live-Test trat dieser Fehler auf:

```
Error:   × Problem with [.../config.d/30-borders.conf], Permission denied
   · No such file or directory (os error 2)
```

> [!bug] „Permission denied" ist irreführend
> Der echte Fehler ist **`os error 2` — No such file or directory**, nicht ein
> Rechteproblem. Nushells `save` legt **keine fehlenden Elternverzeichnisse**
> an. Existiert `~/.config/sway/config.d/` noch nicht, schlägt der Schreibvorgang
> mit dieser doppeldeutigen Meldung fehl.

**Korrektur** — Verzeichnis zuerst anlegen (`mkdir` ist in Nushell rekursiv):

```nu
mkdir ($nu.home-path | path join ".config/sway/config.d")
"default_border pixel 2\ndefault_floating_border pixel 2\n" | save --raw --append ($nu.home-path | path join ".config/sway/config.d/30-borders.conf")
swaymsg reload
```

Kontrolle des Inhalts (verhindert unbemerktes doppeltes Anhängen bei
wiederholten Läufen):

```nu
open --raw ($nu.home-path | path join ".config/sway/config.d/30-borders.conf")
```

> [!tip] Pfadkonvention
> `$nu.home-path | path join` statt `$"($env.HOME)/…"` — konsistent mit den
> übrigen Vault-Kommandos und robuster gegen fehlende Trennzeichen.

---

## 5 — Integration ins NoctaRow-Image 🟡

Der `~/.config`-Pfad ist **nur zum lokalen Testen**. Für den Image-Default
gilt das layered-include-Schema:

- **Image-Default:** Inhalt nach `/usr/share/sway/config.d/30-borders.conf`,
  via `COPY` im Containerfile eingebacken.
- **Host-Override:** bei Bedarf in `/etc/sway/config.d/` — überschattet den
  `/usr/share`-Default (siehe Drop-in-Overshadowing-Learning).
- **Nummerierung:** `30-` bestimmt die Ladereihenfolge; Dateiname = Identität.

> [!danger] Keine eigene `~/.config/sway/config` anlegen
> Der layered-include-Mechanismus durchsucht `~/.config/sway/config.d/` nur,
> solange **keine** eigene `~/.config/sway/config` existiert. Eine solche Datei
> würde den kompletten System-Default (inkl. der `layered-include`-Direktive)
> verdrängen → bekanntes Black-Screen-Problem. Ausschließlich in `config.d/`
> arbeiten.

---

## Offene Punkte

- [ ] Border-Wirkung (`pixel 2` vs. `none`) auf Yoga 920 live sichten
- [ ] `hide_edge_borders smart` / `smart_borders on` auf 4K-Output prüfen
- [ ] Zusammenspiel mit `workspace_layout tabbed` in der Praxis bewerten
- [ ] `30-borders.conf` als `COPY` ins Containerfile übernehmen, dann Status → verifiziert

---

## Verwandte Notizen

- [[README]]
- Sway-Drop-in-Overshadowing (`/etc/` über `/usr/share/`)
- Fenster-Policy / `workspace_layout tabbed`
- Nushell-Syntax-Konventionen (v0.114.1)
