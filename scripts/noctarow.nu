# Noctarow — Build-, Test- und Publish-Modul
# Nushell, nativ auf Fedora Sway Atomic (Yoga) -- die alleinige Build- und
# Zielplattform. Die WSL-Erkennung (ist-wsl) ist historisch: der XPS war
# frueher Build-/Testmaschine, ist es nicht mehr, hat aber ein eigenes
# lauffaehiges Setup. Zweigt zur Laufzeit korrekt auf "nativ" ab.
#
#   use scripts/noctarow.nu *
#   noctarow doctor
#   noctarow build
#   noctarow test-nested
#
# Podman wird durchgaengig ROOTLESS benutzt. Fuer `bootc switch
# --transport containers-storage` muss das Image aber in root's Storage
# liegen -- dafuer gibt es `noctarow to-root`.

const IMAGE = "quay.io/metarow/noctarow"
const BASE  = "quay.io/fedora-ostree-desktops/sway-atomic"
const WSLG_SOCKET = "/mnt/wslg/runtime-dir/wayland-0"

# --- Helfer -----------------------------------------------------------------

# Architektur der laufenden Maschine als OCI-Name
def oci-arch []: nothing -> string {
    match (uname | get machine) {
        "aarch64" => "arm64"
        "x86_64"  => "amd64"
        $other    => { error make {msg: $"Unbekannte Architektur: ($other)"} }
    }
}

# Laufen wir unter WSL?
def ist-wsl []: nothing -> bool {
    $WSLG_SOCKET | path exists
}

# Findet den Wayland-Socket der laufenden Session -- WSLg oder nativ.
def wayland-socket []: nothing -> string {
    if (ist-wsl) {
        return $WSLG_SOCKET          # WSL: immer das Ziel, nie den Symlink
    }

    let runtime = ($env.XDG_RUNTIME_DIR? | default "")
    if ($runtime | is-empty) {
        error make { msg: "XDG_RUNTIME_DIR ist nicht gesetzt - laeuft hier eine Wayland-Session?" }
    }

    let name = ($env.WAYLAND_DISPLAY? | default "wayland-0")
    let sock = ($runtime | path join $name)

    if not ($sock | path exists) {
        let da = (glob $"($runtime)/wayland-*" | where {|f| not ($f | str ends-with ".lock") })
        error make { msg: $"Wayland-Socket nicht gefunden: ($sock). Vorhanden: ($da | str join ', ')" }
    }

    $sock
}

# --- Diagnose ---------------------------------------------------------------

# Prüft die Build-Umgebung. Erst laufen lassen, dann bauen.
export def "noctarow doctor" [] {
    let wsl = (ist-wsl)
    print $"(ansi cyan)Umgebung: (if $wsl { 'WSL (WSLg)' } else { 'nativ' })(ansi reset)"

    let propagation = (findmnt -n -o PROPAGATION / | str trim)
    let controllers = (podman info --format '{{.Host.CgroupControllers}}' | str trim)
    let rootless    = (podman info --format '{{.Host.Security.Rootless}}' | str trim)
    let sock        = (try { wayland-socket } catch { null })
    let dri         = ("/dev/dri" | path exists)
    let frei        = (df --output=avail -BG /var | lines | last | str trim)

    [
        { pruefung: "Mount-Propagation /", ist: $propagation, erwartet: "shared",  ok: ($propagation == "shared") }
        { pruefung: "cgroup-Controller",   ist: $controllers, erwartet: "cpu memory pids", ok: ($controllers =~ "memory") }
        { pruefung: "rootless podman",     ist: $rootless,    erwartet: "true",    ok: ($rootless == "true") }
        { pruefung: "Wayland-Socket",      ist: ($sock | default "fehlt"), erwartet: "vorhanden", ok: ($sock != null) }
        { pruefung: "/dev/dri (Render)",   ist: (if $dri { "vorhanden" } else { "fehlt" }), erwartet: (if $wsl { "optional" } else { "vorhanden" }), ok: ($wsl or $dri) }
        { pruefung: "frei auf /var",       ist: $frei,        erwartet: ">= 20G",  ok: (($frei | str replace "G" "" | into int) >= 20) }
    ]
    | update ok { |r| if $r.ok { $"(ansi green)✓(ansi reset)" } else { $"(ansi red)✗(ansi reset)" } }
}

# Zeigt, welche Config-Dateien das Basis-Image mitbringt.
export def "noctarow inspect-base" [tag: string = "44"] {
    podman run --rm $"($BASE):($tag)" sh -c '
        echo "=== /usr/share/sway/config.d/"; ls -1 /usr/share/sway/config.d/
        echo "=== /etc/sway/config.d/";       ls -1A /etc/sway/config.d/
        echo "=== input-Bloecke?";            grep -rn "xkb_layout\|type:keyboard" /usr/share/sway/ /etc/sway/ || echo "  keine"
    '
}

# Architekturen des Basis-Images.
export def "noctarow base-arches" [tag: string = "44"] {
    skopeo inspect --raw $"docker://($BASE):($tag)"
    | from json
    | get manifests
    | select platform.os platform.architecture
}

# --- Build ------------------------------------------------------------------

# Baut das Image für die lokale Architektur. Rootless.
export def "noctarow build" [
    --tag (-t): string = "44"       # Fedora-Major als Tag
    --noctalia-ref: string = "main" # Branch oder Tag von noctalia-shell
    --no-cache
] {
    let arch = (oci-arch)
    let full = $"($IMAGE):($tag)-($arch)"

    mut args = [
        build
        --tag $full
        --build-arg $"FEDORA_MAJOR=($tag)"
        --build-arg $"NOCTALIA_REF=($noctalia_ref)"
    ]
    if $no_cache { $args = ($args | append "--no-cache") }
    $args = ($args | append ".")

    print $"(ansi cyan)→ ($full)(ansi reset)"
    ^podman ...$args

    # Zusätzlich untagged als lokaler Kurzname
    podman tag $full $"localhost/noctarow:($tag)"
    print $"(ansi green)fertig:(ansi reset) ($full)  +  localhost/noctarow:($tag)"
}

# Zeigt die lokal gebauten Noctarow-Images in beiden Storages.
export def "noctarow images" [] {
    let rootless = (do -i { podman images --format '{{.Repository}}:{{.Tag}}\t{{.ID}}' } | default "")
    let root     = (do -i { sudo podman images --format '{{.Repository}}:{{.Tag}}\t{{.ID}}' } | default "")

    let zeilen = {|txt, wo|
        $txt | lines | where {|l| $l =~ "noctarow" } | each {|l|
            let teile = ($l | split row "\t")
            { storage: $wo, image: ($teile | get 0), id: ($teile | get 1? | default "") }
        }
    }

    (do $zeilen $rootless "rootless") ++ (do $zeilen $root "root")
}

# --- Test -------------------------------------------------------------------

# Startet Sway aus dem Image als Fenster in der laufenden Wayland-Session.
# WSL: Software-Rendering (pixman). Yoga/nativ: echte GPU via /dev/dri.
#
# --cap-add=SYS_NICE ist zwingend: Fedoras sway traegt `cap_sys_nice=ep`.
# Beim execve gilt  pP' = (X & fP) | (pI & fI)  -- fehlt SYS_NICE im Bounding
# Set X (Podmans Default hat es NICHT), kann der Prozess die permitted-Caps der
# Datei nicht bekommen und der Kernel bricht mit EPERM ab:
#   "exec container process `/usr/sbin/sway`: Operation not permitted"
# Betrifft rootless wie rootful, mit und ohne keep-id. bash laeuft, weil es
# keine File-Caps hat.
export def "noctarow test-nested" [
    --tag (-t): string = "44"
    --shell                          # statt sway eine Shell im Container öffnen
    --software                       # Software-Rendering erzwingen (Debug)
] {
    let sock = (wayland-socket)
    let gpu = ((not (ist-wsl)) and ("/dev/dri" | path exists) and (not $software))

    let cmd = if $shell { [bash] } else { [sway -c /etc/sway/config] }
    let render = if $gpu { [] } else { [-e WLR_RENDERER=pixman] }
    let dri = if $gpu { [--device /dev/dri] } else { [] }
    let modus = if $gpu { "GPU (/dev/dri)" } else { "Software (pixman)" }

    print $"Socket: ($sock)  |  Rendering: ($modus)"

    (^podman run --rm -it
        --security-opt label=disable
        --userns=keep-id
        --cap-add=SYS_NICE
        -e HOME=/tmp
        -e LANG=C.UTF-8
        -e XDG_RUNTIME_DIR=/tmp
        -e WAYLAND_DISPLAY=wayland-0
        -e WLR_BACKENDS=wayland
        -e XDG_CURRENT_DESKTOP=sway
        ...$render
        ...$dri
        -v $"($sock):/tmp/wayland-0"
        $"localhost/noctarow:($tag)"
        ...$cmd)
}

# Fragt das aktive XKB-Layout der laufenden Sway-Instanz ab.
# Im nested Sway ausführen, oder von außen mit gesetztem SWAYSOCK.
export def "noctarow keyboard-check" [] {
    swaymsg -t get_inputs
    | from json
    | where type == "keyboard"
    | select identifier xkb_active_layout_name
}

# Zeigt Ausgaben und Skalierung der laufenden Sway-Instanz.
export def "noctarow output-check" [] {
    swaymsg -t get_outputs
    | from json
    | select name make model scale current_mode.width current_mode.height
}

# --- Ausrollen --------------------------------------------------------------

# Kopiert das rootless gebaute Image in root's containers-storage.
#
# Noetig, weil `bootc switch --transport containers-storage` als root laeuft
# und deshalb NUR /var/lib/containers/storage sieht. Der Build ist rootless,
# das Image liegt also in ~/.local/share/containers/storage.
#
# Achtung: das Image liegt danach ZWEIMAL auf der Platte (~6 GB je Kopie).
export def "noctarow to-root" [--tag (-t): string = "44"] {
    let lokal = $"localhost/noctarow:($tag)"

    if (^podman image exists $lokal | complete | get exit_code) != 0 {
        error make { msg: $"($lokal) liegt nicht im rootless Storage. Erst `noctarow build --tag ($tag)`." }
    }

    print $"(ansi cyan)($lokal): rootless → root ...(ansi reset)"
    podman save $lokal | sudo podman load

    print $"(ansi green)im root-Storage:(ansi reset)"
    sudo podman images --format '{{.Repository}}:{{.Tag}}' | lines | where {|l| $l =~ "noctarow" } | each {|l| print $"  ($l)" }

    print ""
    print $"(ansi yellow)Naechster Schritt -- bewusst selbst ausfuehren:(ansi reset)"
    print $"  sudo bootc switch --transport containers-storage ($lokal)"
    print $"  sudo systemctl reboot"
    print ""
    print $"(ansi yellow)Rueckweg, falls der neue Stand nicht taugt:(ansi reset)"
    print $"  sudo bootc rollback"
    print $"  sudo systemctl reboot"
}

# --- Disk-Image -------------------------------------------------------------

# Erzeugt aus dem lokalen Image eine bootfaehige VHDX fuer Hyper-V.
#
# NUR fuer die WSL-Umgebung (XPS). Auf dem Yoga gegenstandslos: dort wird
# direkt per `noctarow to-root` + `bootc switch` ausgerollt.
#
# Laeuft NUR auf ext4 mit shared mounts -- bootc-image-builder braucht
# Loop-Devices im privilegierten Container. Vorher `noctarow doctor`.
export def "noctarow disk" [--tag (-t): string = "44"] {
    if not (ist-wsl) {
        error make { msg: "`noctarow disk` ist fuer die WSL-Umgebung gedacht. Auf dem Yoga: `noctarow to-root` + `bootc switch`." }
    }

    # `df --output=fstype` statt `df -T | awk` -- das Fedora-WSL-Image ist
    # minimal und bringt kein awk mit.
    let fstyp = (df --output=fstype . | lines | last | str trim)
    if $fstyp != "ext4" {
        error make { msg: $"Dateisystem ist ($fstyp), nicht ext4. Nicht unter /mnt/c bauen." }
    }

    mkdir output

    print $"(ansi cyan)bootc-image-builder ...(ansi reset)"
    (^podman run --rm -it --privileged
        --security-opt label=type:unconfined_t
        -v $"(pwd)/output:/output"
        -v /var/lib/containers/storage:/var/lib/containers/storage
        quay.io/centos-bootc/bootc-image-builder:latest
        --type raw
        --local $"localhost/noctarow:($tag)")

    let raw = "output/image/disk.raw"
    if not ($raw | path exists) {
        error make { msg: $"bootc-image-builder hat kein ($raw) erzeugt." }
    }

    let vhdx = $"output/noctarow-($tag).vhdx"
    print $"(ansi cyan)qemu-img → ($vhdx)(ansi reset)"
    qemu-img convert -O vhdx -o subformat=dynamic $raw $vhdx

    ls $vhdx | select name size
}

# --- Publish ----------------------------------------------------------------

# Pusht das arch-spezifische Image. Login vorher manuell: `podman login quay.io`
export def "noctarow push" [--tag (-t): string = "44"] {
    let arch = (oci-arch)
    let full = $"($IMAGE):($tag)-($arch)"
    print $"(ansi yellow)Push: ($full)(ansi reset)"
    podman push $full
}

# Baut die Manifest-List aus den bereits gepushten arch-Images
# und pusht sie unter dem Sammel-Tag. Nur ausführen, wenn BEIDE
# Architekturen oben liegen.
export def "noctarow manifest" [--tag (-t): string = "44"] {
    let list = $"($IMAGE):($tag)"

    do -i { podman manifest rm $list }
    podman manifest create $list
    podman manifest add $list $"docker://($IMAGE):($tag)-amd64"
    podman manifest add $list $"docker://($IMAGE):($tag)-arm64"
    podman manifest push --all $list $"docker://($list)"

    print $"(ansi green)Manifest-List gepusht:(ansi reset) ($list)"
    skopeo inspect --raw $"docker://($list)" | from json | get manifests | select platform.architecture
}

# --- Host-Overrides ---------------------------------------------------------

# Kopiert maschinenspezifische Drop-ins nach /etc/sway/config.d/.
# Auf dem Zielrechner ausführen, nicht im Image.
export def "noctarow apply-host" [host: string] {
    let dir = $"hosts/($host)"
    if not ($dir | path exists) {
        error make { msg: $"Kein Host-Verzeichnis: ($dir)" }
    }

    ls $"($dir)/*.conf" | get name | each { |f|
        let ziel = $"/etc/sway/config.d/($f | path basename)"
        print $"($f) → ($ziel)"
        sudo install -m 0644 $f $ziel
    }

    let kanshi = $"($dir)/kanshi-config"
    if ($kanshi | path exists) {
        mkdir ~/.config/kanshi
        cp $kanshi ~/.config/kanshi/config
        print $"($kanshi) → ~/.config/kanshi/config"
    }

    let noctalia = $"($dir)/noctalia-settings.json"
    if ($noctalia | path exists) {
        mkdir ~/.config/noctalia
        cp $noctalia ~/.config/noctalia/settings.json
        print $"($noctalia) → ~/.config/noctalia/settings.json"
    }
}

# Prüft vor einem `bootc upgrade`, ob eine lokale /etc-Datei den Image-
# Fix für den Noctalia-Startpfad ueberschreiben wuerde.
#
# 95-noctalia.conf liegt im Image unter /usr/share/sway/config.d/ und wird
# bei jedem Upgrade komplett ersetzt -- der klassische 3-Wege-Merge betrifft
# diese Datei NICHT. Riskant ist nur eine gleichnamige Datei unter
# /etc/sway/config.d/ (oder eine Handaenderung in /etc/sway/config), die laut
# Sway's layered-include Vorrang vor der Image-Version haette. Auf dem
# Zielrechner ausführen, nicht im Image.
export def "noctarow etc-drift-check" [] {
    let treffer = (sudo ostree admin config-diff | lines | where {|l| $l =~ "sway" })

    if ($treffer | is-empty) {
        print $"(ansi green)Kein lokal abweichendes /etc/sway -- Image-Fix greift ungehindert.(ansi reset)"
        return
    }

    print $"(ansi yellow)Lokal abweichende Dateien unter /etc/sway:(ansi reset)"
    $treffer | each {|l| print $"  ($l)" }

    if ($treffer | any {|l| $l =~ "95-noctalia.conf" }) {
        print ""
        print $"(ansi red)Achtung:(ansi reset) /etc/sway/config.d/95-noctalia.conf ueberschreibt die Image-Version."
        print "Vermutlich ein manueller Workaround aus der Fehlersuche -- entfernen, bevor der Fix greifen kann:"
        print "  sudo rm /etc/sway/config.d/95-noctalia.conf"
    }
}
