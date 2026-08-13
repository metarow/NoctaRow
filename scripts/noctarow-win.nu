# Noctarow — Windows-Seite
# Läuft in Nushell auf dem Windows-Host (aarch64-pc-windows-msvc).
#
# Installation:
#   mkdir ~/.config/nushell/scripts
#   cp \\wsl.localhost\FedoraLinux-44\home\fritz\projekte\noctarow\scripts\noctarow-win.nu ~/.config/nushell/scripts/
#
# Dann in ~/.config/nushell/config.nu:
#   use ~/.config/nushell/scripts/noctarow-win.nu *

# WSL-Pfad, nicht Windows-Pfad. Geht an `wsl --cd`, das die Tilde NICHT
# expandiert -- deshalb absolut.
const PROJEKT = "/home/fritz/projekte/noctarow"

const DISTRO = "FedoraLinux-44"

# Windows-Ablage für VHDX. Muss NTFS sein: Hyper-V kann keine virtuelle
# Festplatte von \\wsl.localhost anhängen.
const VHDX_DIR = 'C:\Hyper-V\noctarow'

# UNC-Pfad ins Projekt, für gelegentlichen Dateizugriff von Windows aus.
export def "nw path" [] {
    $"\\\\wsl.localhost\\($DISTRO)($PROJEKT | str replace -a '/' '\\')"
}

# --- WSL-Verwaltung ---------------------------------------------------------

# Installierte Distros als Tabelle.
#
# `wsl --list --verbose` gibt UTF-16LE aus und ist je nach Nushell-Version
# schwer zu parsen. `--quiet` liefert nur Namen und ist robuster.
export def "nw distros" [] {
    wsl --list --quiet
    | lines
    | each { |l| $l | str replace -a "\u{0}" "" | str trim }
    | where { |l| $l != "" }
    | wrap name
}

# Sicherung einer Distro anlegen, bevor sie entfernt wird.
export def "nw backup" [distro: string] {
    # $env.HOME gibt es auf Windows nicht. $nu.home-path ist plattformneutral.
    let dir = ($nu.home-path | path join "wsl-backup")
    mkdir $dir
    let ziel = ($dir | path join $"($distro).tar")
    print $"Export → ($ziel)"
    wsl --export $distro $ziel
    ls $ziel | select name size
}

# WSL neu starten, z.B. nach Änderungen an /etc/wsl.conf.
export def "nw restart" [] {
    wsl --shutdown
    sleep 3sec
    print "Mount-Propagation nach Neustart:"
    wsl -d $DISTRO -- findmnt -n -o PROPAGATION /
}

# Nushell-Session in Fedora öffnen, direkt im Projektverzeichnis.
export def "nw shell" [] {
    wsl -d $DISTRO --cd $PROJEKT
}

# --- Durchreichen ins Projekt -----------------------------------------------

# Beliebigen noctarow-Befehl in der WSL-Distro ausführen.
#   nw run "noctarow build --tag 45"
export def "nw run" [cmd: string] {
    let inner = $"use scripts/noctarow.nu *; ($cmd)"
    wsl -d $DISTRO --cd $PROJEKT -- nu -c $inner
}

export def "nw doctor" [] { nw run "noctarow doctor" }
export def "nw build" [--tag (-t): string = "44"] { nw run $"noctarow build --tag ($tag)" }
export def "nw test" [] { nw run "noctarow test-nested" }

# --- VHDX: von ext4 nach NTFS -----------------------------------------------

# Erzeugt das Disk-Image in WSL und legt die fertige VHDX auf NTFS ab.
#
# Warum zweistufig: bootc-image-builder und qemu-img brauchen ext4 und
# Loop-Devices, laufen also in WSL. Hyper-V wiederum liest keine VHDX von
# \\wsl.localhost. Also drüben bauen, herüber kopieren.
export def "nw sync-vhdx" [
    --tag (-t): string = "44"
    --skip-build                      # nur kopieren, VHDX existiert schon
] {
    if not $skip_build {
        print $"(ansi cyan)Baue VHDX in WSL ...(ansi reset)"
        nw run $"noctarow disk --tag ($tag)"
    }

    mkdir $VHDX_DIR

    # Der Kopiervorgang läuft WSL-seitig über drvfs. Das ist zuverlässiger
    # als ein Windows-Zugriff auf \\wsl.localhost.
    let ziel_wsl = ($VHDX_DIR | str replace 'C:\' '/mnt/c/' | str replace -a '\' '/')
    print $"(ansi cyan)Kopiere → ($VHDX_DIR)(ansi reset)"
    wsl -d $DISTRO --cd $PROJEKT -- cp $"output/noctarow-($tag).vhdx" $ziel_wsl

    ls $"($VHDX_DIR)\\noctarow-($tag).vhdx" | select name size modified
}

# --- Hyper-V ----------------------------------------------------------------
# Nur zum Testen des GEBOOTETEN Images. Braucht Windows Pro und eine
# Administrator-Shell.

def assert-admin [] {
    let ist_admin = (
        powershell -NoProfile -Command
        "([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)"
        | str trim | str downcase
    )
    if $ist_admin != "true" {
        error make { msg: "Hyper-V-Befehle brauchen eine Administrator-Shell." }
    }
}

# Legt eine Generation-2-VM mit deaktiviertem Secure Boot an.
export def "nw vm-create" [
    --tag (-t): string = "44"
    --name: string = "noctarow-test"
    --memory: string = "8GB"
    --cpus: int = 4
] {
    assert-admin

    let vhdx = $"($VHDX_DIR)\\noctarow-($tag).vhdx"
    if not ($vhdx | path exists) {
        error make { msg: $"VHDX fehlt: ($vhdx) — erst `nw sync-vhdx`" }
    }

    powershell -NoProfile -Command $"
        New-VM -Name '($name)' -Generation 2 -MemoryStartupBytes ($memory) -VHDPath '($vhdx)'
        Set-VMProcessor -VMName '($name)' -Count ($cpus)
        Set-VMFirmware -VMName '($name)' -EnableSecureBoot Off
        Set-VM -Name '($name)' -AutomaticCheckpointsEnabled `$false
    "
    print $"VM '($name)' angelegt. Start: (ansi cyan)nw vm-start(ansi reset)"
}

export def "nw vm-start" [--name: string = "noctarow-test"] {
    assert-admin
    powershell -NoProfile -Command $"Start-VM -Name '($name)'"
    vmconnect.exe localhost $name
}

export def "nw vm-remove" [--name: string = "noctarow-test"] {
    assert-admin
    powershell -NoProfile -Command $"
        Stop-VM -Name '($name)' -TurnOff -Force -ErrorAction SilentlyContinue
        Remove-VM -Name '($name)' -Force
    "
    print $"VM '($name)' entfernt. Die VHDX bleibt liegen."
}

export def "nw vm-list" [] {
    powershell -NoProfile -Command "Get-VM | Select-Object Name,State,Uptime | ConvertTo-Json"
    | from json
}
