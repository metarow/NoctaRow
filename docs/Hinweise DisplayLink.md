Damit ist die Lage eindeutig: `/run/ostree-booted` = `true` plus `rpm-ostree`/`bootc` vorhanden → der Dozenten-PC läuft **immutable** (Fedora Sway Atomic). Es gibt hier kein mutables Fedora zum schnellen `dnf install`. Das heißt konkret:

- **`rpm-ostree install` ist auch als „Schnelltest" der falsche Weg** – nicht nur wegen deiner bootc-Disziplin, sondern weil ein Kernelmodul (evdi baut per DKMS/akmod) auf ostree ohnehin frickelig zu layern und schlecht rückstandsfrei zu entfernen ist. Kein guter Shortcut.
- Der einzig saubere Machbarkeitstest, der **weder** das Atomic-System anfasst **noch** deine Prinzipien verletzt, ist eine **wegwerfbare mutable Umgebung auf genau dieser Hardware**: ein Fedora-Workstation-**Live-USB**, hier gebootet. Gleicher Ivy-Bridge-Intel, gleiches DisplayLink-Gerät, aber `dnf`/COPR frei nutzbar und nach dem Ausschalten spurlos weg.

## Warum Live-USB und nicht direkt der akmod-Build

Die riskante Variable ist nicht evdi selbst, sondern **ob Sway/wlroots den evdi-Node rendert**. Es wäre Verschwendung, erst eine akmod-Build-Stage im Containerfile zu bauen und mehrere Image-Iterationen zu drehen, nur um dann festzustellen, dass Sway streikt. Der Live-USB beantwortet in _einer_ Sitzung beide Fragen:

1. Baut/lädt evdi + füttert der Daemon einen dritten DRM-Node? (Treiber-Kette)
2. Zeigt **Sway** ihn an? (der wlroots-Knackpunkt)

Erst wenn beides ✓ ist, lohnt der akmod-Weg ins Image.

## Test-Ablauf im Live-USB

> [!warning] Secure Boot vor dem Test im BIOS deaktivieren Der DKMS-gebaute evdi ist unsigniert. In einer Live-Sitzung ist MOK-Enrollment kaum praktikabel – für den Test Secure Boot aus, für das spätere Image löst du das über signierte akmods sauber. Prüfen: `mokutil --sb-state`.

Fedora-Workstation-Live booten (nicht die Atomic-Variante), dann – nushell ist in Fedora, also gleich nachziehen:

```nu
sudo dnf install nushell
nu
```

In der nushell-Sitzung:

```nu
# COPR bündelt evdi + DisplayLinkManager, zieht kernel-devel/dkms als Deps
sudo dnf copr enable crashdummy/Displaylink
sudo dnf install displaylink

# Daemon + Modul aktivieren
sudo systemctl enable --now displaylink.service
sudo modprobe evdi

# DisplayLink-Monitor ab- und wieder anstecken, dann:
lsmod | lines | find evdi        # jetzt NICHT mehr leer
ls /dev/dri                       # ein zusätzliches cardN erwartet
```

**Erster Beweis (Treiber-Kette):** In GNOME sollte der dritte Monitor jetzt in den Anzeige-Einstellungen auftauchen – Mutter hat ausgereiften evdi-Support. Erscheint er hier nicht, ist die Hardware-Kette das Problem und Sway ohnehin chancenlos.

**Zweiter Beweis (Sway selbst):** Wenn der Node da ist, den eigentlichen Zielfall testen – Sway in derselben Live-Sitzung nachinstallieren und aus einem TTY starten:

```nu
sudo dnf install sway

# Render-GPU (i915) zuerst, evdi-Node zuletzt; genaue Zuordnung vorher prüfen:
drm_info | lines | find -i driver evdi i915
with-env { WLR_DRM_DEVICES: "/dev/dri/card0:/dev/dri/card1" } { sway --unsupported-gpu }
```

Läuft Sway und zeigt `swaymsg -t get_outputs` den dritten (DisplayLink-)Output → grünes Licht für den akmod-Weg ins Image. Bleibt er schwarz/Sway crasht, hast du die Antwort _bevor_ du Containerfile-Zeit investierst – dann ist die ehrliche Konsequenz, den dritten Monitor am Dozenten-PC nicht über Sway zu erzwingen.

Ich schreibe dir den Containerfile-akmod-Stage-Block gern aus, sobald der Live-Test steht – vorher wäre er unverifizierte Spekulation, und der wlroots-Teil ist zu wackelig, um ihn blind zu bauen. Sag Bescheid, wie der Live-Test ausgeht.