FROM quay.io/fedora-ostree-desktops/sway-atomic:44

# Terra (Fyra Labs): Quelle für noctalia-shell + noctalia-qs, baut für x86_64 und aarch64.
# Gevendort statt per curl geholt -> nachvollziehbar im Git.
COPY terra.repo /etc/yum.repos.d/terra.repo

# noctalia-qs verlangt Qt 6.11; dnf hebt qt6-qtbase als normale Abhängigkeit an.
# Das "eingefrorene Basis-Paket"-Problem von rpm-ostree install existiert hier nicht.
RUN dnf install -y \
        noctalia-shell \
        nushell \
        helix \
    && dnf clean all \
    && rm -rf /var/cache/libdnf5 /var/cache/dnf

# Sway-Drop-ins nach /usr/share: Dateiname = Identität, Prefix = Ladereihenfolge.
# Leere 90-*-Dateien verdrängen waybar und swayidle (Kollision mit Noctalia).
COPY sway/30-borders.conf    /usr/share/sway/config.d/30-borders.conf
COPY sway/50-keyboard.conf   /usr/share/sway/config.d/50-keyboard.conf
COPY sway/70-output.conf     /usr/share/sway/config.d/70-output.conf
COPY sway/90-bar.conf        /usr/share/sway/config.d/90-bar.conf
COPY sway/90-swayidle.conf   /usr/share/sway/config.d/90-swayidle.conf
COPY sway/95-noctalia.conf   /usr/share/sway/config.d/95-noctalia.conf

# environment.noctarow ANHAENGEN, nicht ersetzen -- /usr/share/sway/environment
# existiert bei Fedora nicht und wird von niemandem gelesen.
# /etc/sway/environment wird von /usr/bin/start-sway gesourct.
COPY sway/environment.noctarow /tmp/environment.noctarow
RUN cat /tmp/environment.noctarow >> /etc/sway/environment \
    && rm /tmp/environment.noctarow

# foot liest die System-Default über $XDG_CONFIG_DIRS, nicht /usr/share
COPY foot/foot.ini /etc/xdg/foot/foot.ini

# Login-Screen: HiDPI + Tastatur
COPY sddm/    /usr/lib/sddm/sddm.conf.d/
COPY tmpfiles/ /usr/lib/tmpfiles.d/

RUN bootc container lint
