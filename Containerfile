FROM quay.io/fedora-ostree-desktops/sway-atomic:44

# Manche Pakete verlangen ein vorhandenes /var/roothome, sonst bricht der Build ab.
RUN mkdir -p /var/roothome

# Terra (Fyra Labs): Quelle für noctalia-shell/noctalia-qs, x86_64 + aarch64.
# Gevendort inkl. excludepkgs=terra-obsolete und skip_if_unavailable=False.
COPY terra.repo /etc/yum.repos.d/terra.repo

# --- Schicht 1: Noctalia (dnf) ---
# noctalia-qs verlangt Qt 6.11; dnf hebt qt6-qtbase als normale Abhängigkeit an.
# Bewusst NICHT im Image: nushell und helix -- die kommen per brew nach /var.
RUN dnf install -y noctalia-shell \
    && dnf clean all \
    && rm -rf /var/cache/libdnf5 /var/cache/dnf

# Guard: erfolgreicher dnf-Exit-Code ist KEIN Beweis der Installation
# (Obsoletes-Umleitung, siehe terra-obsolete-Vorfall).
RUN rpm -q noctalia-shell

# Der QML-Baum aus dem RPM liegt unter /etc/xdg/quickshell/ und würde bei
# jedem `bootc switch` durch den ostree Drei-Wege-Merge laufen -- ändert
# jemand lokal auch nur eine .qml, gilt sie als Admin-Modifikation und wird
# künftig nicht mehr ersetzt, der Baum zerfällt in zwei Versionen. Deshalb
# eine Kopie nach /usr spiegeln und von dort starten: /usr ist read-only,
# der Merge fasst es nicht an. Die RPM-Kopie unter /etc bleibt als
# Experimentierfläche liegen, rpm -V bleibt sauber.
RUN mkdir -p /usr/share/noctarow \
    && cp -a /etc/xdg/quickshell/noctalia-shell /usr/share/noctarow/noctalia-shell

# --- Schicht 2: Build-Toolchain für Homebrew (read-only in /usr) ---
# brew selbst landet zur Laufzeit in /var/home/linuxbrew, nie im Image.
RUN dnf -y install \
        @development-tools \
        gcc gcc-c++ make \
        procps-ng curl file git \
        libxcrypt-compat \
    && dnf clean all \
    && rm -rf /var/cache/libdnf5 /var/cache/dnf

# --- Schicht 3: Overlay (Sway, foot, SDDM, tmpfiles, Bootstrap, Wrapper) ---
COPY overlay/ /

# Guard: qs -p muss auf das Verzeichnis zeigen, nie auf shell.qml --
# sonst startet der Prozess, scheitert an den relativen QML-Imports
# und blockiert stumm den Instanznamen.
RUN ! grep -rq "noctalia-shell/shell.qml" /usr/share/sway/ \
    && test -f /etc/xdg/quickshell/noctalia-shell/shell.qml

# Guard: der gespiegelte /usr-Baum muss existieren und qs muss ihn finden --
# sonst startet Sway gegen einen Pfad, den kein bootc-Update mehr pflegt.
RUN test -x /usr/bin/qs \
    && test -f /usr/share/noctarow/noctalia-shell/shell.qml

RUN chmod +x /usr/libexec/noctarow/homebrew-bootstrap.sh \
             /usr/libexec/noctarow/terminal-shell \
    && systemctl --global enable homebrew-bootstrap.service

# Sway-Umgebung: append, nicht ersetzen -- start-sway sourct /etc/sway/environment.
RUN cat /usr/share/noctarow/environment.noctarow >> /etc/sway/environment

# Qualitätssicherung
RUN bootc container lint

LABEL org.opencontainers.image.title="Noctarow" \
      org.opencontainers.image.description="Fedora Sway Atomic + Noctalia + Homebrew-Toolchain (nushell/helix via brew)" \
      org.opencontainers.image.vendor="MetaRow Software UG" \
      containers.bootc="1"
