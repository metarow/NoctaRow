---
titel: DisplayLink-Monitor unter Fedora Sway Atomic (evdi) – Ergebnis
aliases: [DisplayLink evdi, USB-Monitor Sway Atomic, evdi bootc]
tags: [fedora, sway-atomic, bootc, displaylink, evdi, wlroots, akmod, dozenten-pc, noctarow]
zielgeraet: Dozenten-PC (Ivy-Bridge Intel iGPU, x86_64)
erstellt: 2026-07-15
verifiziert_am: 2026-09-15
status: verifiziert
---

# 23 — DisplayLink-Monitor unter Fedora Sway Atomic (evdi) – Ergebnis

> [!success] Ergebnis
> Dritter Monitor per DisplayLink läuft unter Fedora Sway Atomic 44 auf einem selbstgebauten bootc-Image. `bootc switch` → Reboot → Monitor erkannt → System stabil. Der wlroots/evdi-Weg, der historisch als fragil gilt, funktioniert auf **reiner Intel-Grafik** mit dem Flag `--unsupported-gpu`.
> **Offen:** foot-Terminal startet im Testimage nicht (vermutlich fehlende Config, s. u.).

## Ausgangslage

| Komponente | Wert |
|---|---|
| System | Fedora Sway Atomic 44, `/run/ostree-booted` = `true` |
| GPU | Intel iGPU (Ivy-Bridge, Xeon E3 v2-Klasse), Treiber `i915` – **keine** dGPU mehr |
| DisplayLink-Gerät | `17e9:4301` DisplayLink USB3 to HDMI |
| Base-Image-Kernel | `7.1.3-200.fc44.x86_64` |
| Ziel | dritter Monitor, persistent im Image |

> [!tip] Intel-only war der Glücksfall
> Die bekannten evdi-Ausfälle unter Sway hängen fast alle an NVIDIA-/Multi-GPU-Konstellationen (wlroots-Issue #1823). Nach dem Ausbau der alten NVIDIA-Karte existiert dieses Problem auf diesem Rechner nicht mehr – deshalb lief es hier auf Anhieb.

## Die drei Bausteine

Ohne **alle drei** erscheint kein Monitor:

1. **`evdi`-Kernelmodul** (Open Source) – legt den virtuellen DRM-Node an
2. **`DisplayLinkManager`-Daemon** (proprietär) – füttert den Node; udev-aktiviert
3. **`sway --unsupported-gpu`** – ohne den Flag ignoriert wlroots den evdi-Node

---

## Weg 1: Diagnose

USB-Monitore sind zweierlei – erst klären, welcher Fall vorliegt:

- **USB-C mit DisplayPort-Alt-Mode** → nativ über die iGPU, kein Treiber. Wird erkannt.
- **Echter DisplayLink** (Chip `17e9`) → braucht evdi + Daemon. Wird **nie** automatisch erkannt.

```nu
lsusb | lines | find -i displaylink          # 17e9 = DisplayLink
lspci | lines | find -i nvidia               # leer = kein Multi-GPU-Problem
lsmod | lines | find evdi                     # leer = Modul fehlt
ls /dev/dri                                    # nur card0 + renderD128 = kein evdi-Node
"/run/ostree-booted" | path exists             # true = Atomic
```

Befund: `17e9:4301`, kein evdi, nur `card0`/`renderD128` → klassischer DisplayLink-Fall auf Atomic.

---

## Weg 2: Machbarkeitstest im Live-System

> [!note] Warum erst Live-USB, nicht direkt ins Image?
> Die riskante Unbekannte war nicht evdi, sondern **ob wlroots/Sway den Node rendert**. Ein Fedora-Workstation-Live-USB auf derselben Hardware beantwortet das in einer Sitzung – mutable, spurlos, hardware-identisch – ohne erst Image-Iterationen zu drehen. `rpm-ostree install` ist als Shortcut ungeeignet (Kernelmodule schlecht rückstandsfrei zu layern, bricht `bootc upgrade`).

Installation via COPR `crashdummy/Displaylink`, dann evdi gegen den **laufenden** Kernel bauen. Ergebnis: **drei Monitore aktiv**, dritter über DisplayLink, mit `--unsupported-gpu`.

Damit waren die drei kritischen Punkte bewiesen: evdi baut gegen fc44, der Daemon füttert den Node, **und wlroots rendert ihn**.

---

## Weg 3: Integration ins bootc-Image – die Fallstricke

Der Live-Test war einfach; der Image-Build brachte eine Kette von Stolpersteinen, jeder mit einer übertragbaren Lehre.

> [!bug] 1 – Scriptlets scheitern im Build-Container
> `%post` von `displaylink` ruft `systemctl` und `udevadm`. Im Build gibt es kein PID-1-systemd (`System has not been booted with systemd…`) und kein beschreibbares `/sys` (`Permission denied` auf `uevent`). → **`--setopt=tsflags=noscripts`** bzw. `rpm --noscripts`.
> Merksatz: `systemctl enable` braucht **kein** laufendes systemd (nur Symlinks), `start`/`daemon-reload`/`status` schon.

> [!bug] 2 – Fehlende Build-Stage
> `COPY --from=evdi-builder` ohne zweites `FROM` → Podman sucht `evdi-builder` als **Image** in Registries. Multi-Stage braucht zwei `FROM`, die zweite eröffnet die Final-Stage und wirft die Build-Toolchain weg.

> [!bug] 3 – Kernel-Drift verwaist das Modul (der Kern-Bug)
> Base-Image hat Kernel **200**, evdi wird für 200 gebaut und abgelegt. Ein späteres `dnf install displaylink` in Stage 2 zieht `kernel-devel-matched` → **Kernel-Upgrade auf 201** → System bootet 201, evdi liegt verwaist unter `…/modules/200/extra/`. `modinfo` findet nichts.
> Fix zweifach: **Daemon per `rpm -i --nodeps`** (kein `kernel-devel-matched`, keine Toolchain im Runtime-Image) **und** `exclude=kernel*` in `/etc/dnf/dnf.conf`, damit jeder künftige Kernel-Eingriff **laut** scheitert. Zusätzlich das Modul **nach** dem Daemon einspielen.

> [!bug] 4 – `dnf download` zieht auch das .src.rpm
> Glob `displaylink-*.rpm` erwischte Binär- **und** Source-RPM; RPM scheiterte beim Entpacken der Sources. → `find … ! -name '*.src.rpm'`, arch-agnostisch statt `*.x86_64.rpm`.

> [!bug] 5 – Dienst hat keine [Install]-Sektion
> `systemctl enable displaylink-driver.service` scheitert – der Dienst ist **udev-aktiviert** (`/etc/udev/rules.d/99-displaylink.rules` → `udev.sh`), nicht enable-bar. Die Unit lädt evdi selbst per `ExecStartPre=/sbin/modprobe evdi`. → kein `enable`, nur Existenzprüfungen von Unit + Regel + Skript + Binary.

> [!bug] 6 – Pipe verschluckt den Exit-Status
> `modinfo … | head` liefert den Status von `head`, nicht `modinfo` – ein kaputtes Modul hätte den Build **nicht** gestoppt. → echter Check mit `modinfo … > /dev/null`, Pipe nur für Log-Kosmetik.

### Verifikation vor dem Switch (ohne Reboot)

```nu
# Modul für den Image-Kernel registriert?
sudo podman run --rm localhost/noctarow:evdi-test bash -c 'KVER=$(rpm -q --qf "%{VERSION}-%{RELEASE}.%{ARCH}" kernel-core); modinfo -k $KVER evdi | head -3'
# --nodeps-Gegencheck: alle Libraries da?
sudo podman run --rm localhost/noctarow:evdi-test bash -c 'ldd /usr/libexec/displaylink/DisplayLinkManager 2>&1 | grep -i "not found" || echo "ok"'
# Toolchain draußen? (erwartet: nur libgcc)
sudo podman run --rm localhost/noctarow:evdi-test rpm -qa | lines | find dkms kernel-devel gcc
# Genau ein Kernel?
sudo podman run --rm localhost/noctarow:evdi-test rpm -qa | lines | find kernel-core
```

Alle grün → Switch, Reboot, `swaymsg -t get_outputs` → dritter Monitor.

> [!note] Gegen `localhost/noctarow-displaylink:44` verifiziert (2026-09-08)
> evdi registriert für `kernel-core` des Images, `DisplayLinkManager` ohne
> fehlende Libs, genau ein `kernel-core` — alle drei grün. Der
> Toolchain-Check schlägt hier **erwartungsgemäß** an (`gcc`, `gcc-c++`,
> `kernel-devel` sind vorhanden): Das kommt nicht aus dieser Schicht,
> sondern aus dem Basis-Image selbst (`noctarow:44` installiert bewusst
> eine Compiler-Toolchain für den Homebrew-Bootstrap, siehe
> [[15-noctarow-basis-image]]). Kein Kernel-Drift-Risiko dadurch — die
> `kernel-core`-Version im Basis-Image war schon vor dieser Schicht
> gesetzt und stimmt mit der evdi-Build-`KVER` überein.

> [!note] `--unsupported-gpu` ist der Upstream-Weg
> Fedoras `/etc/sway/environment` führt genau dieses Flag als auskommentiertes Beispiel. Der Weg über `SWAY_EXTRA_ARGS` (von `start-sway` gesourct) ist also vorgesehen – die RPM-eigene `sway.desktop` bleibt unangetastet.
> Beim Merge ins echte Containerfile die **Append-Form** nutzen (`"$SWAY_EXTRA_ARGS --unsupported-gpu"`) statt der Zuweisung, damit spätere Argumente nicht still überschrieben werden.

---

## Offene Punkte

- [ ] **foot startet nicht** im Testimage. Vermutlich nur fehlende `foot.ini` (das Testimage ist das nackte `sway-atomic:44` ohne deine Configs). Prüfen: `foot` aus laufender Session starten, `journalctl -b --user -t foot`. Startet `foot -f monospace:size=12`, ist es die Config.
- [ ] **`WLR_DRM_DEVICES`** – im Live-Test mitgegeben, im Image nur `--unsupported-gpu`. Bisher nicht nötig gewesen; falls Sway den Node je ignoriert, der nächste Hebel.
- [ ] **Secure Boot** – im Test aus. Der Build-MOK ist dem Rechner unbekannt; bei aktivem Secure Boot lädt evdi nicht. Saubere Lösung: eigener Signing-Key + MOK-Enrollment (bündelbar mit cosign).
- [x] **`environment.noctarow`-Kollision** – geprüft: `overlay/usr/share/noctarow/environment.noctarow` setzt `SWAY_EXTRA_ARGS` nicht, keine Kollision. `Containerfile.displaylink` hängt trotzdem in Append-Form an (`SWAY_EXTRA_ARGS="$SWAY_EXTRA_ARGS --unsupported-gpu"`), damit ein künftiger Layer nichts still überschreibt.

## Architekturentscheidung: evdi gehört NICHT ins Basis-Image

> [!important] Abgeleitetes Image statt Basis-Image
> Vier Gründe:
> 1. **Nur der Dozenten-PC** hat den DisplayLink-Adapter – die Yoga (4K-Laptop) braucht ihn nicht.
> 2. Die evdi-Stage **darf nicht gecacht werden** (Kernel-Drift) → baut bei jedem Base-Update komplett neu → dauerhafte CI-Steuer.
> 3. **Fehlerisolation** – Noctalia (reine Repo-Pakete) und evdi (Kernel-gekoppelt, Drittanbieter) getrennt einführen.
> 4. **aarch64-Killer:** Ob `crashdummy/Displaylink` für arm64 baut, ist offen. Im gemeinsamen Basis-Containerfile würde ein fehlender arm64-Build einen **künftigen aarch64-Zweig blockieren**, sollte je eine solche Plattform dazukommen (siehe [[docs/04-quay-veroeffentlichung#Multi-Arch: aktuell zurückgestellt]]).
>
> → eigenes `noctarow-displaylink:latest` (x86_64-only), das `FROM noctarow:latest` ableitet und nur der Dozenten-PC zieht. Passt zur bestehenden `hosts/`-Trennung. Reihenfolge im Projekt: **erst Noctalia ins Basis-Image, dann diese abgeleitete Variante.**

> [!success] Umgesetzt (2026-09-08)
> Noctalia ist im Basis-Image, der Dozenten-PC läuft bereits darauf
> (`rpm-ostree status` zeigt `noctarow:44-amd64` als gebootetes
> Deployment). Die abgeleitete Variante liegt jetzt als
> `Containerfile.displaylink` im Repo (`FROM localhost/noctarow:44`),
> Build/Rollout über `noctarow build-displaylink` +
> `noctarow to-root --image noctarow-displaylink`. Host-Override:
> [[hosts/dozenten-pc/README|hosts/dozenten-pc]].
>
> **Live verifiziert 2026-09-15** nach `bootc switch` + Reboot auf dem
> Dozenten-PC: Kernel `7.1.13-200.fc44`, `evdi` geladen,
> `displaylink-driver.service` aktiv, drei Outputs (`DVI-I-1` via evdi,
> `HDMI-A-1`, `VGA-1`), alle 1920×1080.

---

## Kommentiertes Containerfile

> [!warning] Dies ist das isolierte Testimage
> Basis ist das nackte `sway-atomic:44` – ohne Noctalia, foot-Config, Nushell-Shell. Der evdi-Teil wandert später in ein **abgeleitetes** Image (`FROM noctarow:latest`), nicht ins Basis-Containerfile (s. Architekturentscheidung).

```dockerfile
# =====================================================================
# Noctarow – DisplayLink/evdi Testimage
#
# Stage 1 baut evdi gegen den Kernel des Base-Image.
# Stage 2 spielt nur das fertige Modul + den Daemon ein –
# ohne Build-Toolchain und ohne Kernel-Upgrade.
#
# Build:  sudo podman build -f Containerfile.evdi-test -t noctarow:evdi-test .
# =====================================================================


# =====================================================================
# Stage 1 – evdi gegen den Image-Kernel bauen
# =====================================================================
FROM quay.io/fedora-ostree-desktops/sway-atomic:44 AS evdi-builder

RUN set -eux; \
    KVER=$(rpm -q --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' kernel-core); \
    echo ">>> Kernel im Base-Image: ${KVER}"; \
    \
    dnf install -y dnf-plugins-core; \
    dnf copr enable -y crashdummy/Displaylink; \
    \
    # Build-Toolchain. Kernel-Pakete ausschliessen, damit KVER gueltig bleibt.
    dnf install -y \
        --setopt=exclude='kernel,kernel-core,kernel-modules*' \
        "kernel-devel-${KVER}" \
        gcc make dkms elfutils-libelf-devel; \
    \
    # displaylink ohne Scriptlets: %post ruft systemctl/udevadm,
    # beides scheitert im Build-Container zwangslaeufig.
    dnf install -y --setopt=tsflags=noscripts displaylink; \
    \
    # Diagnostik: liefert das RPM den DKMS-Baum im Payload?
    ls -l /usr/src/; \
    \
    # Ohne %post fehlt das 'dkms add' – nachholen.
    dkms add evdi/1.15.0 || true; \
    dkms status; \
    dkms install evdi/1.15.0 -k "${KVER}"; \
    \
    # Kompression kann .ko oder .ko.xz sein – nicht auf einen Namen festlegen.
    mkdir -p /out; \
    find "/lib/modules/${KVER}" -name 'evdi.ko*' -exec cp -a {} /out/ \; ; \
    ls -l /out; \
    test -n "$(ls -A /out)"


# =====================================================================
# Stage 2 – finales Image
# =====================================================================
FROM quay.io/fedora-ostree-desktops/sway-atomic:44

# ---------------------------------------------------------------------
# Kernel des Base-Image ist verbindlich.
# Ein Kernel-Upgrade in Stage 2 wuerde evdi verwaisen lassen
# (Modul liegt unter .../modules/<alt>/extra, System bootet <neu>).
# Ab hier scheitert jeder dnf-Aufruf, der den Kernel anfassen will – laut.
# ---------------------------------------------------------------------
RUN printf 'exclude=kernel,kernel-core,kernel-modules*,kernel-devel*\n' \
      >> /etc/dnf/dnf.conf

# ---------------------------------------------------------------------
# 1. DisplayLinkManager-Daemon (proprietaer)
#
# Bewusst 'rpm -i --nodeps --noscripts' statt 'dnf install':
#   --nodeps    verhindert die Kette dkms -> kernel-devel-matched -> Kernel-Upgrade
#               und haelt gcc/dkms/kernel-devel aus dem Runtime-Image
#   --noscripts %post startet den Dienst und triggert udev – im Build unmoeglich
# Der DKMS-Baum wird zur Laufzeit nicht gebraucht, das Modul ist vorgebaut.
# ---------------------------------------------------------------------
RUN set -eux; \
    dnf install -y dnf-plugins-core; \
    dnf copr enable -y crashdummy/Displaylink; \
    dnf download --destdir=/tmp/dl displaylink; \
    ls -l /tmp/dl; \
    \
    # dnf laedt auch das .src.rpm mit – gezielt nur das Binaerpaket nehmen.
    # Kein '*.x86_64.rpm', damit der Block arch-agnostisch bleibt.
    PKG=$(find /tmp/dl -name 'displaylink-*.rpm' ! -name '*.src.rpm' | head -1); \
    test -n "$PKG"; \
    echo ">>> Paket: $PKG"; \
    echo ">>> Requires (werden von --nodeps uebergangen):"; \
    rpm -qR "$PKG"; \
    \
    rpm -i --nodeps --noscripts "$PKG"; \
    rm -rf /tmp/dl; \
    \
    dnf clean all; \
    rm -rf /var/cache/libdnf5 /var/cache/dnf /var/log/dnf5.log /run/dnf

# Kernel darf sich bis hierher nicht geaendert haben.
RUN set -eux; \
    test "$(rpm -qa kernel-core | wc -l)" -eq 1; \
    rpm -q kernel-core

# ---------------------------------------------------------------------
# 2. evdi-Modul – bewusst NACH dem Daemon, damit kein spaeterer
#    Paket-Layer den Modulbaum unter dem Modul wegziehen kann.
# ---------------------------------------------------------------------
COPY --from=evdi-builder /out/ /tmp/evdi/

RUN set -eux; \
    KVER=$(rpm -q --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' kernel-core); \
    mkdir -p "/usr/lib/modules/${KVER}/extra"; \
    cp -a /tmp/evdi/evdi.ko* "/usr/lib/modules/${KVER}/extra/"; \
    depmod -a "${KVER}"; \
    rm -rf /tmp/evdi; \
    \
    # Echter Check ohne Pipe – der Exit-Status ist der von modinfo.
    modinfo -k "${KVER}" evdi > /dev/null; \
    echo ">>> evdi registriert fuer ${KVER}:"; \
    modinfo -k "${KVER}" evdi | head -n 3

# evdi frueh laden. Streng genommen redundant – die Unit macht
# ExecStartPre=/sbin/modprobe evdi – aber robuster gegen Timing.
RUN printf 'evdi\n' > /usr/lib/modules-load.d/70-noctarow-evdi.conf

# ---------------------------------------------------------------------
# 3. Daemon-Aktivierung verifizieren
#
# KEIN 'systemctl enable': displaylink-driver.service hat keine
# [Install]-Sektion. Der Dienst wird udev-aktiviert
# (99-displaylink.rules -> udev.sh) beim Anstecken eines 17e9-Geraets.
# ---------------------------------------------------------------------
RUN set -eux; \
    test -f /usr/lib/systemd/system/displaylink-driver.service; \
    test -f /etc/udev/rules.d/99-displaylink.rules; \
    test -x /usr/libexec/displaylink/udev.sh; \
    test -x /usr/libexec/displaylink/DisplayLinkManager; \
    echo ">>> udev-Regel:"; \
    cat /etc/udev/rules.d/99-displaylink.rules

# ---------------------------------------------------------------------
# 4. Sway mit --unsupported-gpu starten
#
# /usr/share/wayland-sessions/sway.desktop ruft 'start-sway' auf, nicht
# sway direkt. start-sway (aus sway-systemd) sourct /etc/sway/environment
# und haengt $SWAY_EXTRA_ARGS unquoted an den exec-Aufruf an.
# Damit bleibt die RPM-eigene .desktop unangetastet.
#
# HINWEIS: Beim Merge ins echte Containerfile die Append-Form nutzen:
#   printf 'SWAY_EXTRA_ARGS="$SWAY_EXTRA_ARGS --unsupported-gpu"\n'
# damit spaetere Argumente nicht still ueberschrieben werden.
# ---------------------------------------------------------------------
RUN set -eux; \
    mkdir -p /etc/sway; \
    printf 'SWAY_EXTRA_ARGS=--unsupported-gpu\n' >> /etc/sway/environment; \
    grep -q 'unsupported-gpu' /etc/sway/environment

RUN bootc container lint
```

## Verwandte Notizen

- [[09-yoga-buildumgebung]]
- [[05-hidpi-und-monitore]]
- [[03-bauen-und-testen]]
