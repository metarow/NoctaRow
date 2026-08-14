#!/usr/bin/bash
set -euo pipefail

BREW=/var/home/linuxbrew/.linuxbrew/bin/brew
[ -x "$BREW" ] && exit 0

export NONINTERACTIVE=1
curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh | bash

# bash-Seite verankern (idempotent)
if ! grep -q 'linuxbrew.*shellenv' "$HOME/.bashrc" 2>/dev/null; then
    echo 'eval "$(/var/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> "$HOME/.bashrc"
fi

# Userland: nushell und helix kommen AUSSCHLIESSLICH hierueber, nie per dnf
"$BREW" install nushell helix jq ripgrep

# nushell-Seite verankern: env.nu, marker-guarded (nushell liest kein profile.d)
NU_ENV="$HOME/.config/nushell/env.nu"
mkdir -p "$(dirname "$NU_ENV")"
if ! grep -q 'NOCTAROW-BREW' "$NU_ENV" 2>/dev/null; then
    cat >> "$NU_ENV" << 'NUEOF'
# >>> NOCTAROW-BREW >>>
$env.PATH = ($env.PATH | prepend [
    "/var/home/linuxbrew/.linuxbrew/bin"
    "/var/home/linuxbrew/.linuxbrew/sbin"
])
$env.HOMEBREW_PREFIX = "/var/home/linuxbrew/.linuxbrew"
$env.HOMEBREW_CELLAR = "/var/home/linuxbrew/.linuxbrew/Cellar"
$env.HOMEBREW_REPOSITORY = "/var/home/linuxbrew/.linuxbrew/Homebrew"
# <<< NOCTAROW-BREW <<<
NUEOF
fi
