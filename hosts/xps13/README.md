# Dell XPS 13 9345 (Snapdragon X Elite, aarch64)

Nur Build- und Testmaschine, kein Deployment-Ziel.

Fuer echtes Metal-Deployment fehlen: gepatchter Kernel mit X1E80100-Support,
DeviceTree x1e80100-dell-xps13-9345.dtb, Secure Boot aus. Eigenes Projekt.

Getestet wird hier ausschliesslich:
  - nested Sway gegen WSLg (Konfiguration)
  - Hyper-V-VM (Image-Plumbing)
