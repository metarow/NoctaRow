---
titel: Veröffentlichung auf quay.io
teil_von: "[[README]]"
tags: [quay, registry, oci, manifest, multi-arch, cosign]
---

# 04 — Veröffentlichung auf quay.io

Ziel: `quay.io/metarow/noctarow` als **öffentliches Repository**, Multi-Arch
(`amd64` + `arm64`), sodass jede Maschine der Flotte per `bootc switch` daran
andocken kann.

## Einrichtung (einmalig, im Browser)

> [!warning] Zugangsdaten
> Die folgenden Schritte erledigst du selbst in der Weboberfläche. Passwörter,
> Tokens und Robot-Credentials gehören nirgends in dieses Repository und
> nirgends in ein Skript.

1. Konto auf `quay.io` anlegen bzw. anmelden.
2. **Organisation** anlegen: `metarow`.
   Nicht das persönliche Konto verwenden — die Organisation ist die
   Rechtsform, unter der du veröffentlichst, und überlebt einen Personwechsel.
3. **Repository** `noctarow` anlegen, Sichtbarkeit **Public**.
4. Unter *Organization → Robot Accounts* einen Robot anlegen, z. B.
   `metarow+noctarow_push`, und ihm auf dem Repository `Write` geben.

Der Robot bekommt ein generiertes Token. Das ist die Identität, mit der CI
oder deine Build-Maschinen pushen — nicht dein persönliches Passwort.

## Anmelden

```nu
podman login quay.io
```

Podman fragt interaktiv nach Benutzer und Token und legt die Credentials unter
`$XDG_RUNTIME_DIR/containers/auth.json` ab.

> [!tip] `$XDG_RUNTIME_DIR` überlebt keinen Neustart
> Es wird bei jedem Boot neu angelegt. Für dauerhaftes Login:
> `podman login --authfile ~/.config/containers/auth.json quay.io` und dann
> `$env.REGISTRY_AUTH_FILE = "~/.config/containers/auth.json"` in
> `~/.config/nushell/env.nu`.

## Tag-Strategie

| Tag | Bedeutung | Wer nutzt es |
|---|---|---|
| `44` | Manifest-List, aktuell, folgt Fedora 44 | Entwicklung, Test |
| `44-amd64`, `44-arm64` | arch-spezifisch, Push-Ziele | nur intern |
| `44.20260709` | gepinnter Stand, unveränderlich | **Schulungsflotte** |
| `stable` | Alias auf den geprüften gepinnten Stand | Schulungsflotte |

> [!important] Für die Flotte nie ein Floating-Tag
> Ein Rechner, der mitten im Kurs auf ein frisch gebautes Image aktualisiert,
> ist ein Rechner, der mitten im Kurs kaputtgeht. Die Flotte zeigt auf
> `stable`, und du verschiebst `stable` bewusst, nach dem Test.

## Multi-Arch: aktuell zurückgestellt

Der Yoga ist die einzige aktive Build- und Zielmaschine (x86_64). Es gibt
derzeit **keine** lokale aarch64-Build-Maschine im Projekt — eine Manifest-List
mit `arm64` ist damit vertagt, bis eine solche Plattform wieder ansteht.

```nu
use scripts/noctarow.nu *
noctarow build --tag 44
noctarow push  --tag 44          # → quay.io/metarow/noctarow:44-amd64
```

Braucht es später doch `arm64`, ist der native GitHub-Actions-Runner der
richtige Weg (kein manueller Zweitrechner nötig) — siehe
[„Alternative: nativ bauen ohne zweite Maschine"](#alternative-nativ-bauen-ohne-zweite-maschine)
und [[docs/10-github-repository#Schritt 5 — Was `ubuntu-24.04-arm` bedeutet]].
Erst dann wird eine Manifest-List gebaut:

```nu
noctarow manifest --tag 44       # → quay.io/metarow/noctarow:44
```

Das Skript baut die Liste aus den bereits in der Registry liegenden
Arch-Images (`docker://…`), nicht aus lokalen Layern. Es lädt also keine
fremde Architektur herunter.

Kontrolle:

```nu
skopeo inspect --raw docker://quay.io/metarow/noctarow:44
| from json | get manifests | select platform.architecture
```

## Gepinnten Stand veröffentlichen

```nu
let heute = (date now | format date "%Y%m%d")

podman manifest push --all $"quay.io/metarow/noctarow:44" $"docker://quay.io/metarow/noctarow:44.($heute)"
skopeo copy $"docker://quay.io/metarow/noctarow:44.($heute)" docker://quay.io/metarow/noctarow:stable
```

## Alternative: nativ bauen ohne zweite Maschine

Für ein künftiges `arm64`-Ziel: GitHub Actions baut inzwischen kostenlos auf
**arm64-Runnern für öffentliche Repositories**. Ein Workflow mit einer
`matrix` über `ubuntu-24.04` und `ubuntu-24.04-arm` erzeugt beide Images und
die Manifest-List in einem Lauf — ganz ohne lokale Zweitmaschine.

Was du dafür brauchst: den Robot-Token als Repository-Secret. Was du dafür
bekommst: reproduzierbare Builds ohne Zustand aus deiner Werkstatt.

> [!note] Nicht per binfmt emulieren
> `podman build --platform linux/arm64` auf dem x86-Desktop funktioniert mit
> `qemu-user-static`, dauert aber ein Vielfaches. Für ein Image mit
> Qt6-Abhängigkeiten ist das keine gute Zeitinvestition.

## Signieren (optional, aber sinnvoll)

Das Basis-Image ist cosign-signiert — die vielen `sha256-….sig`-Tags im
`skopeo list-tags`-Output sind genau das. Für ein Image, das auf fremden
Rechnern bootet, ist eine eigene Signatur nicht übertrieben:

```bash
cosign generate-key-pair
cosign sign --key cosign.key quay.io/metarow/noctarow:stable
```

Der öffentliche Schlüssel wandert dann ins Image nach
`/usr/etc/containers/policy.json`, damit `bootc upgrade` nur signierte Images
akzeptiert. **Der private Schlüssel gehört nicht ins Repository.**

`.gitignore` enthält deshalb bereits `cosign.key` und `*.pem`.
