---
title: "Troubleshooting-Log: bootc-Image atomic-brew"
date: 2026-07-21
tags:
  - troubleshooting
  - fedora-atomic
  - bootc
  - homebrew
  - github
  - ssh
status: aktiv
---

# Troubleshooting-Log: bootc-Image `atomic-brew`

Chronologische Übersicht der aufgetretenen Probleme beim Bau und Deployment des Homebrew-bootc-Images.

---

## 1. cosign nicht installiert

**Problem:** `cosign generate-key-pair` schlägt fehl, da `cosign` auf dem Atomic-System nicht verfügbar ist. Installation per `rpm-ostree`/`dnf` ist auf Atomic-Systemen unüblich, solange die Toolchain nicht ins Image gehört.

**Lösung:** Ohne Homebrew (noch nicht installiert) per Container oder Binary:
```bash
podman run --rm -v $PWD:/work:Z -w /work \
  gcr.io/projectsigstore/cosign generate-key-pair
```
oder
```bash
mkdir -p ~/.local/bin
curl -Lo ~/.local/bin/cosign \
  https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64
chmod +x ~/.local/bin/cosign
```

---

## 2. `just` nicht installiert

**Problem:** `just build` schlägt fehl mit `bash: just: Kommando nicht gefunden`.

**Lösung:** Befehle direkt mit `podman` ausführen, oder `just` als Binary nach `~/.local/bin` installieren:
```bash
curl -fsSL https://just.systems/install.sh | bash -s -- --to ~/.local/bin
export PATH="$HOME/.local/bin:$PATH"
```

---

## 3. `bootc container lint`-Warnungen im Build

**Problem:** Erster Build meldet 3 Warnungen (`nonempty-run-tmp`, `var-log`, `var-tmpfiles`) durch DNF-Cache-Reste in `/var` und `/run`.

**Lösung:** Aufräumbefehle direkt an den `dnf`-Install-Layer im `Containerfile` anhängen:
```dockerfile
RUN dnf -y install ... && \
    dnf clean all && \
    rm -rf /var/cache/libdnf5 /var/lib/dnf /var/log/* /var/cache/ldconfig/* \
           /run/dnf /run/svnserve
```
Zweiter Build: 13 Checks passed, 0 Warnungen.

---

## 4. `git push` – SSH-Timeout auf Port 22

**Problem:**
```
ssh: connect to host github.com port 22: Connection timed out
```
Port 22 ist im Netzwerk blockiert.

**Lösung:** GitHub über Port 443 ansprechen (`ssh.github.com`):
```
Host github.com
    Hostname ssh.github.com
    Port 443
    User git
```
Alternativ HTTPS mit PAT statt SSH nutzen.

---

## 5. SSH `Permission denied (publickey)`

**Problem:** Nach Umstellung auf Port 443 verbindet SSH, aber ohne hinterlegten Key:
```
git@ssh.github.com: Permission denied (publickey).
```

**Ursache:** Vorhandene Keys und `config`-Datei stammten vom bestehenden Windows-System und wurden 1:1 nach Linux kopiert – daraus resultierten auch die Folgeprobleme 6. und 7.

**Lösung:** Siehe Punkte 6 und 7.

---

## 6. IdentityFile-Pfade in `~/.ssh/config` (Windows → Linux)

**Problem:** Config aus Windows-Kontext (`C:/Users/CBaier/.ssh/...`) auf Fedora übernommen; Pfade passen nicht zum Linux-Home.

**Lösung:** Pfade auf `~/.ssh/...` umstellen:
```
IdentityFile ~/.ssh/id_ed25519
IdentityFile ~/.ssh/macmini
```

---

## 7. Unsichere Dateiberechtigungen bei privaten Keys

**Problem:**
```
WARNING: UNPROTECTED PRIVATE KEY FILE!
Permissions 0644 for '/home/cbaier/.ssh/id_ed25519' are too open.
```

**Lösung:** Korrekte Berechtigungen setzen:
```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_ed25519 ~/.ssh/macmini
chmod 644 ~/.ssh/*.pub ~/.ssh/config
```

