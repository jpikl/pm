#!/usr/bin/env sh

set -eu

PMS="yay pacman apt dnf"

usage() {
    echo "Package manager wrapper (supports: $PMS)"
    echo
    echo "Usage: ${0##*/} <command>"
    echo
    echo "Commands:"
    echo "  i, install          Interactively select packages to install"
    echo "  i, install <pkg>... Install one or more packages"
    echo "  u, upgrade          Upgrade all installed packages"
    echo "  r, remove           Interactively select packages to remove"
    echo "  r, remove <pkg>...  Remove one or more packages"
    echo "  n, info <pkg>       Print package information"
    echo "  l, list <source>    List packages (source: installed, available)"
    echo "  li                  Alias for 'list installed'"
    echo "  la                  Alias for 'list available'"
    echo "  s, search <source>  Interactively search packages (source: installed, available)"
    echo "  si                  Alias for 'search installed'"
    echo "  sa                  Alias for 'search available'"
    echo "  f, refresh          Refresh local package database"
    echo "  h, help             Print this help"
}

main() {
    if [ $# -eq 0 ]; then
        die_wrong_usage "expected <command> argument"
    fi

    if [ "$1" = h ] || [ "$1" = -h ] || [ "$1" = help ] || [ "$1" = --help ]; then
        usage
        exit
    fi

    if [ ! "${COLOR-}" ]; then
        if [ -t 1 ]; then
            COLOR="always"
        else
            COLOR="never"
        fi
    fi

    if [ ! "${PM-}" ]; then
        for NAME in $PMS; do
            if is_command "$NAME"; then
                PM=$NAME
                break
            fi
        done
        if [ ! "${PM-}" ]; then
            die "no supported package manager found ($PMS)"
        fi
    fi

    COMMAND=$1
    shift

    case "$COMMAND" in
    i | install) install "$@" ;;
    u | upgrade) upgrade ;;
    r | remove) remove "$@" ;;
    n | info) info "$@" ;;
    l | list) list "$@" ;;
    li) list installed ;;
    la) list available ;;
    s | search) search "$@" ;;
    si) search installed ;;
    sa) search available ;;
    f | refresh) refresh ;;
    *) die_wrong_usage "invalid <command> argument '$COMMAND'" ;;
    esac
}

# =============================================================================
# Commands
# =============================================================================

install() {
    if [ $# -eq 0 ]; then
        search available | PM=$PM COLOR=$COLOR xargs -ro "$0" install
    else
        "${PM}_install" "$@"
    fi
}

upgrade() {
    "${PM}_refresh"
    "${PM}_upgrade"
}

remove() {
    if [ $# -eq 0 ]; then
        search installed | PM=$PM COLOR=$COLOR xargs -ro "$0" remove
    else
        "${PM}_remove" "$@"
    fi
}

info() {
    "${PM}_info" "$@"
}

list() {
    check_source "$@"
    "${PM}_list_$1"
}

search() {
    check_source "$@"
    list "$1" | filter "$1"
}

refresh() {
    "${PM}_refresh"
}

# =============================================================================
# Utils
# =============================================================================

die() {
    echo >&2 "${0##*/}: $1"
    exit 1
}

die_wrong_usage() {
    die "$1, run '${0##*/} help' for usage"
}

is_command() {
    [ -x "$(command -v "$1")" ]
}

check_source() {
    if [ $# -eq 0 ]; then
        die_wrong_usage "expected <source> argument"
    elif [ "$1" != installed ] && [ "$1" != available ]; then
        die_wrong_usage "invalid <source> argument '$1'"
    fi
}

filter() {
    if is_command fzf; then
        COLUMN=$("${PM}_list_${1}_column" 2>/dev/null || echo 1)
        fzf --multi --no-sort --ansi --layout=reverse --exact --cycle --preview="PM=$PM COLOR=$COLOR $0 info {$COLUMN}" | cut -d" " -f"$COLUMN"
    else
        die "fzf is not available, run '${0##*/} install fzf' first"
    fi
}

# =============================================================================
# Pacman
# =============================================================================

pacman_install() {
    for PKG in "$@"; do
        if [ "$PKG" = yay ] || [ "$PKG" = yay-bin ]; then
            # Custom install procedure for yay
            pacman_install_yay "$PKG"
            # Re-run the installation for the remaining packages (should use yay)
            printf "%s\n" "$@" | grep -Fv "$PKG" | xargs -ro "$0" install
            return
        fi
    done
    sudo pacman -S "$@"
}

pacman_install_yay() {
    sudo pacman -S --needed git base-devel
    TMP_DIR=$(mktemp -du)
    git clone "https://aur.archlinux.org/$1.git" "$TMP_DIR"
    cd "$TMP_DIR"
    makepkg -si
}

pacman_remove() {
    sudo pacman -Rsc "$@"
}

pacman_upgrade() {
    sudo pacman -Su
}

pacman_info() {
    pacman -Si --color="$COLOR" "$1"
}

pacman_list_installed() {
    pacman -Q --color="$COLOR"
}

pacman_list_available() {
    pacman -Sl --color="$COLOR"
}

pacman_list_available_column() {
    echo 2
}

pacman_refresh() {
    sudo pacman -Sy
}

# =============================================================================
# Yay
# =============================================================================

yay_install() {
    yay -S "$@"
}

yay_upgrade() {
    yay -Su
}

yay_remove() {
    yay -Rsc "$@"
}

yay_info() {
    yay -Si --color="$COLOR" "$1"
}

yay_list_installed() {
    yay -Q --color="$COLOR"
}

yay_list_available() {
    # Use yay to print only the AUR packages because
    # 1. We want non-AUR packages first in the list.
    # 2. Its much faster to get results using pacman.
    pacman_list_available
    yay -Sla --color"=$COLOR"
}

yay_list_available_column() {
    echo 2
}

yay_refresh() {
    yay -Sy
}

# =============================================================================
# Apt
# =============================================================================

apt_install() {
    sudo apt install "$@"
}

apt_upgrade() {
    sudo apt upgrade
}

apt_remove() {
    sudo apt remove "$@"
}

apt_info() {
    apt show "$1"
}

apt_list_installed() {
    apt list --installed | tr '/' ' '
}

apt_list_available() {
    apt list | tr '/' ' '
}

apt_refresh() {
    sudo apt update
}

# =============================================================================
# Dnf
# =============================================================================

dnf_install() {
    sudo dnf install "$@"
}

dnf_upgrade() {
    sudo dnf upgrade
}

dnf_remove() {
    sudo dnf remove "$@"
}

dnf_info() {
    dnf info --color="$COLOR" "$1"
}

dnf_list_installed() {
    dnf list --installed --color="$COLOR"
}

dnf_list_available() {
    dnf list --color="$COLOR"
}

dnf_refresh() {
    sudo dnf check-update
}

# =============================================================================
# Run
# =============================================================================

main "$@"
