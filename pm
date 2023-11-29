#!/usr/bin/env sh

set -eu

# Package managers are detected in this order
PMS="paru yay pacman apt dnf"

usage() {
    echo "Package manager wrapper (supports: $PMS)"
    echo
    echo "Usage: ${0##*/} <command>"
    echo
    echo "Commands:"
    echo "  i,  install          Interactively select packages to install."
    echo "  i,  install <pkg>... Install one or more packages."
    echo "  r,  remove           Interactively select packages to remove."
    echo "  r,  remove <pkg>...  Remove one or more packages."
    echo "  u,  upgrade          Upgrade all installed packages."
    echo "  f,  refresh          Refresh local package database."
    echo "  n,  info <pkg>       Print package information."
    echo "  la, list all         List all packages."
    echo "  li, list installed   List installed packages."
    echo "  sa  search all       Interactively search between all packages."
    echo "  si  search installed Interactively search between installed packages."
    echo "  w,  which            Print which package manager is being used."
    echo "  h,  help             Print this help."
}

main() {
    if [ $# -eq 0 ]; then
        die_wrong_usage "expected <command> argument"
    fi

    if [ "$1" = h ] || [ "$1" = -h ] || [ "$1" = help ] || [ "$1" = --help ]; then
        usage
        exit
    fi

    if [ ! "${PM_COLOR-}" ]; then
        if [ -t 1 ]; then
            PM_COLOR="always"
        else
            PM_COLOR="never"
        fi
    fi

    # Output styling
    if [ "$PM_COLOR" = always ]; then
        ST_NAME='"\033[1m"'
        ST_GROUP='" \033[1;35m"'
        ST_VERSION='" \033[1;32m"'
        ST_STATUS='" \033[1;36m"'
        ST_RESET='"\033[0m"'
    else
        ST_NAME='""'
        ST_GROUP='" "'
        ST_VERSION='" "'
        ST_STATUS='" "'
        ST_RESET='""'
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
    la) list all ;;
    s | search) search "$@" ;;
    si) search installed ;;
    sa) search all ;;
    f | refresh) refresh ;;
    w | which) which ;;
    *) die_wrong_usage "invalid <command> argument '$COMMAND'" ;;
    esac
}

# =============================================================================
# Commands
# =============================================================================

install() {
    if [ $# -eq 0 ]; then
        search all | PM=$PM PM_COLOR=$PM_COLOR xargs -ro "$0" install
    else
        "${PM}_install" "$@"
    fi
}

remove() {
    if [ $# -eq 0 ]; then
        search installed | PM=$PM PM_COLOR=$PM_COLOR xargs -ro "$0" remove
    else
        "${PM}_remove" "$@"
    fi
}

upgrade() {
    "${PM}_refresh"
    "${PM}_upgrade"
}

refresh() {
    "${PM}_refresh"
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

which() {
    echo "$PM"
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
    elif [ "$1" != installed ] && [ "$1" != all ]; then
        die_wrong_usage "invalid <source> argument '$1'"
    fi
}

filter() {
    if is_command fzf; then
        fzf --multi --no-sort --ansi --layout=reverse --exact --cycle --preview="PM=$PM PM_COLOR=$PM_COLOR $0 info {1}" | cut -d" " -f1
    else
        die "fzf is not available, run '${0##*/} install fzf' first"
    fi
}

# =============================================================================
# Pacman
# =============================================================================

pacman_install() {
    for PKG in "$@"; do
        if [ "$PKG" = paru ] || [ "$PKG" = paru-bin ] || [ "$PKG" = yay ] || [ "$PKG" = yay-bin ]; then
            # Custom install procedure for aur helpers
            pacman_install_aur "$PKG"
            # Re-run the installation for the remaining packages (should use the installed helper as PM)
            printf "%s\n" "$@" | grep -Fv "$PKG" | xargs -ro "$0" install
            return
        fi
    done
    sudo pacman -S --needed "$@"
}

pacman_install_aur() {
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

pacman_refresh() {
    sudo pacman -Sy
}

pacman_info() {
    pacman -Si --color="$PM_COLOR" "$1"
}

pacman_list_all() {
    pacman -Sl | pacman_format_all
}

pacman_list_installed() {
    pacman -Q | pacman_format_installed
}

pacman_format_all() {
    awk "{ print $ST_NAME \$2 $ST_GROUP \$1 $ST_VERSION \$3 $ST_STATUS \$4 $ST_RESET }"
}

pacman_format_installed() {
    awk "{ print $ST_NAME \$1 $ST_VERSION \$2 $ST_RESET }"
}

# =============================================================================
# Paru
# =============================================================================

paru_install() {
    paru -S --needed "$@"
}

paru_remove() {
    paru -Rsc "$@"
}

paru_upgrade() {
    paru -Su
}

paru_refresh() {
    paru -Sy
}

paru_info() {
    paru -Si --color="$PM_COLOR" "$1"
}

paru_list_all() {
    paru -Sl | pacman_format_all
}

paru_list_installed() {
    paru -Q | pacman_format_installed
}

# =============================================================================
# Yay
# =============================================================================

yay_install() {
    yay -S --needed "$@"
}

yay_remove() {
    yay -Rsc "$@"
}

yay_upgrade() {
    yay -Su
}

yay_refresh() {
    yay -Sy
}

yay_info() {
    yay -Si --color="$PM_COLOR" "$1"
}

yay_list_all() {
    # We want non-AUR results first and pacman is also much faster than yay here.
    pacman_list_all
    yay -Sla | pacman_format_all
}

yay_list_installed() {
    yay -Q | pacman_format_installed
}

# =============================================================================
# Apt
# =============================================================================

apt_install() {
    sudo apt install "$@"
}

apt_remove() {
    sudo apt remove "$@"
}

apt_upgrade() {
    sudo apt upgrade
}

apt_refresh() {
    sudo apt update
}

apt_info() {
    # Using `apt show` is not recommended due to unstable CLI
    apt-cache show "$1"
}

apt_list_all() {
    TMP=$(mktemp)
    dpkg-query --show -f '${package} [installed]\n' >"$TMP"
    apt-cache pkgnames |
        LC_ALL=C sort |
        join -j1 -a1 - "$TMP" |
        awk "{ print $ST_NAME \$1 $ST_STATUS \$2 $ST_RESET }"
    rm "$TMP"
}

apt_list_installed() {
    dpkg-query --show | awk "{ print $ST_NAME \$1 $ST_VERSION \$2 $ST_RESET }"
}

# =============================================================================
# Dnf
# =============================================================================

dnf_install() {
    sudo dnf install "$@"
}

dnf_remove() {
    sudo dnf remove "$@"
}

dnf_refresh() {
    sudo dnf check-update
}

dnf_upgrade() {
    sudo dnf upgrade
}

dnf_info() {
    # Skip the first header line
    dnf info -q --color="$PM_COLOR" "$1" | tail -n+2
}

dnf_list_all() {
    TMP=$(mktemp)
    dnf repoquery -q --installed --qf '%{name} [installed]' >"$TMP"
    dnf repoquery -q --qf='%{name} %{repoid} %{evr}' |
        join -j1 -a1 - "$TMP" |
        awk "{ print $ST_NAME \$1 $ST_GROUP \$2 $ST_VERSION \$3 $ST_STATUS \$4 $ST_RESET }"
    rm "$TMP"
}

dnf_list_installed() {
    dnf repoquery -q --installed --qf '%{name} %{evr}' | awk "{ print $ST_NAME \$1 $ST_VERSION \$2 $ST_RESET }"
}

# =============================================================================
# Run
# =============================================================================

main "$@"
