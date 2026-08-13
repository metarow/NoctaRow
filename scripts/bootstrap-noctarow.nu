#!/usr/bin/env nu
# ---------------------------------------------------------------------------
# Noctarow — Bootstrap
#
# Läuft in Nushell AUF WINDOWS, einmalig, aus dem Download-Ordner heraus.
# Verteilt das Projekt korrekt auf WSL- und Windows-Seite.
#
#   nu bootstrap-noctarow.nu --dry-run
#   nu bootstrap-noctarow.nu --distro FedoraLinux-44 --user fritz
#
# Der Windows-Zielordner wird ueber $nu.default-config-dir ermittelt --
# auf Windows also %APPDATA%\nushell\scripts, nicht ~/.config.
#
# Danach kann dieses Skript gelöscht werden. Alles Weitere läuft über
# `noctarow` (in WSL) und `nw` (auf Windows).
# ---------------------------------------------------------------------------

# Prüft, ob ein Pfad in der Distro existiert. `complete` fängt den Exit-Code,
# damit ein erwartetes "nicht vorhanden" kein Fehler ist.
def wsl-exists [distro: string, pfad: string, typ: string = "-d"]: nothing -> bool {
    (wsl -d $distro -- test $typ $pfad | complete | get exit_code) == 0
}

def main [
    --tarball: path = "noctarow.tar.gz"   # relativ zum aktuellen Verzeichnis
    --distro: string = "FedoraLinux-44"
    --user: string = "fritz"              # Linux-Benutzer in der Distro
    --dry-run                             # nur zeigen, nichts tun
] {
    let projekt_wsl = $"/home/($user)/projekte/noctarow"

    # $env.HOME gibt es auf Windows nicht (dort: USERPROFILE), und der
    # Nushell-Konfigurationsordner liegt unter %APPDATA%\nushell, nicht
    # unter ~/.config. $nu.default-config-dir ist plattformunabhaengig genau
    # das Verzeichnis, aus dem config.nu geladen wird.
    let config_dir = $nu.default-config-dir
    let win_scripts = ($config_dir | path join "scripts")

    print $"(ansi cyan_bold)Noctarow Bootstrap(ansi reset)"
    print $"  Distro       : ($distro)"
    print $"  Ziel in WSL  : ($projekt_wsl)"
    print $"  Windows-Modul: ($win_scripts | path join 'noctarow-win.nu')"
    print ""

    # --- Vorbedingungen ----------------------------------------------------

    if not ($tarball | path exists) {
        error make { msg: $"Archiv nicht gefunden: ($tarball). Im Download-Ordner ausführen." }
    }

    let distros = (
        wsl --list --quiet
        | lines
        | each { |l| $l | str replace -a "\u{0}" "" | str trim }
        | where { |l| $l != "" }
    )
    if not ($distro in $distros) {
        error make { msg: $"Distro '($distro)' nicht gefunden. Vorhanden: ($distros | str join ', ')" }
    }

    # Windows-Pfad des Tarballs in einen WSL-Pfad übersetzen.
    # C:\Users\fritz\Downloads\x.tar.gz  ->  /mnt/c/Users/fritz/Downloads/x.tar.gz
    #
    # Kein `str replace -r` mit Closure -- das nimmt Nushell nicht. Am
    # Doppelpunkt trennen ist ohnehin lesbarer.
    let abs = ($tarball | path expand)
    let teile = ($abs | split row ':')
    if ($teile | length) < 2 {
        error make { msg: $"Kein Windows-Pfad mit Laufwerksbuchstabe: ($abs)" }
    }
    let laufwerk = ($teile | first | str downcase)
    let rest = ($teile | skip 1 | str join ':' | str replace -a '\' '/')
    let tar_wsl = $"/mnt/($laufwerk)($rest)"
    print $"  Archiv \(WSL): ($tar_wsl)"
    print ""

    if $dry_run {
        print $"(ansi yellow)--dry-run: es wird nichts geschrieben.(ansi reset)"
        return
    }

    # --- WSL-Seite ---------------------------------------------------------

    print $"(ansi cyan)[1/4](ansi reset) Entpacken nach ($projekt_wsl)"

    if (wsl-exists $distro $projekt_wsl) {
        print $"(ansi yellow)  Verzeichnis existiert bereits. Überspringe Entpacken.(ansi reset)"
        print $"  Zum Neuaufsetzen: wsl -d ($distro) -- rm -rf ($projekt_wsl)"
    } else {
        wsl -d $distro -- mkdir -p $"/home/($user)/projekte"
        wsl -d $distro -- tar xzf $tar_wsl -C $"/home/($user)/projekte"
    }

    # --- ext4 prüfen -------------------------------------------------------

    print $"(ansi cyan)[2/4](ansi reset) Dateisystem prüfen"

    # Kein awk! Das Fedora-WSL-Image ist minimal. `df --output=fstype` reicht.
    let df = (wsl -d $distro -- df --output=fstype $projekt_wsl | complete)

    let fstyp = if $df.exit_code == 0 {
        ($df.stdout | lines | last | str trim)
    } else {
        "unbekannt"
    }

    match $fstyp {
        "ext4" => { print $"  (ansi green)✓(ansi reset) ext4" }
        "unbekannt" => {
            print $"  (ansi yellow)?(ansi reset) konnte nicht ermittelt werden — bitte selbst prüfen:"
            print $"    wsl -d ($distro) -- df -T ($projekt_wsl)"
        }
        _ => {
            print $"  (ansi red)✗(ansi reset) ($fstyp) statt ext4."
            print $"    Podman-Builds über 9p/drvfs sind langsam und unzuverlässig."
            print $"    Das Projekt darf nicht unter /mnt/c liegen."
        }
    }

    # --- Git ---------------------------------------------------------------

    print $"(ansi cyan)[3/4](ansi reset) Git initialisieren"

    if (wsl-exists $distro $"($projekt_wsl)/.git") {
        print "  bereits ein Repository, übersprungen"
    } else {
        # Ohne konfigurierte Identität scheitert `git commit`. Das ist kein
        # Grund, den Bootstrap abzubrechen -- und schon gar keiner, ungefragt
        # eine globale Git-Konfiguration zu schreiben.
        let ident = (
            wsl -d $distro -- git config --global user.email | complete
        )

        wsl -d $distro --cd $projekt_wsl -- git init -q

        if $ident.exit_code == 0 and ($ident.stdout | str trim) != "" {
            wsl -d $distro --cd $projekt_wsl -- sh -c "git add -A && git commit -q -m 'Initialer Stand'"
            print $"  (ansi green)✓(ansi reset) Repository angelegt, initialer Commit"
        } else {
            print $"  (ansi yellow)!(ansi reset) Repository angelegt, aber kein Commit."
            print $"    Git kennt deine Identität nicht. In WSL:"
            print $"      git config --global user.name  \"Fritz-Rainer Döbbelin\""
            print $"      git config --global user.email \"…\""
            print $"    Danach:  cd ($projekt_wsl); git add -A; git commit -m 'Initialer Stand'"
        }
    }

    # --- Windows-Seite -----------------------------------------------------

    print $"(ansi cyan)[4/4](ansi reset) Windows-Modul installieren"

    mkdir $win_scripts
    let quelle = $"\\\\wsl.localhost\\($distro)($projekt_wsl | str replace -a '/' '\\')\\scripts\\noctarow-win.nu"
    cp $quelle $"($win_scripts)/noctarow-win.nu"
    print $"  (ansi green)✓(ansi reset) ($win_scripts)/noctarow-win.nu"

    # --- Abschluss ---------------------------------------------------------

    print ""
    print $"(ansi green_bold)Fertig.(ansi reset)"
    print ""
    print "Noch von Hand, weil es deine Konfiguration ist:"
    print ""
    print $"  (ansi cyan)# Windows: ($config_dir)/config.nu(ansi reset)"
    print $"  use ($win_scripts | path join 'noctarow-win.nu')  *"
    print ""
    print $"  (ansi cyan)# In scripts/noctarow-win.nu prüfen:(ansi reset)"
    print $"  const PROJEKT = \"($projekt_wsl)\""
    print $"  const DISTRO  = \"($distro)\""
    print ""
    print "Dann:"
    print $"  (ansi cyan)nw doctor(ansi reset)      # Build-Umgebung prüfen"
    print $"  (ansi cyan)nw build(ansi reset)       # Image bauen"
    print $"  (ansi cyan)nw test(ansi reset)        # nested Sway starten"
    print ""
    print $"Dieses Skript wird nicht mehr gebraucht und kann gelöscht werden."
}
