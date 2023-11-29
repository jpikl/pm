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
    echo "  i,  install          Interactively select packages to install"
    echo "  i,  install <pkg>... Install one or more packages"
    echo "  u,  upgrade          Upgrade all installed packages"
    echo "  r,  remove           Interactively select packages to remove"
    echo "  r,  remove <pkg>...  Remove one or more packages"
    echo "  n,  info <pkg>       Print package information"
    echo "  la, list all         List all packages"
    echo "  li, list installed   List installed packages"
    echo "  sa  search all       Interactively search between all packages"
    echo "  si  search installed Interactively search between installed packages"
    echo "  f,  refresh          Refresh local package database"
    echo "  w,  which            Print which package manager is being used"
    echo "  h,  help             Print this help"
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

    # AWK styling
    if [ "$PM_COLOR" = always ]; then
        AS_NAME='"\033[1m"'
        AS_GROUP='" \033[1;35m"'
        AS_VERSION='" \033[1;32m"'
        AS_STATUS='" \033[1;36m"'
        AS_RESET='"\033[0m"'
    else
        AS_NAME='""'
        AS_GROUP='" "'
        AS_VERSION='" "'
        AS_STATUS='" "'
        AS_RESET='""'
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

upgrade() {
    "${PM}_refresh"
    "${PM}_upgrade"
}

remove() {
    if [ $# -eq 0 ]; then
        search installed | PM=$PM PM_COLOR=$PM_COLOR xargs -ro "$0" remove
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

pacman_info() {
    pacman -Si --color="$PM_COLOR" "$1"
}

pacman_list_installed() {
    pacman -Q | pacman_format_installed
}

pacman_list_all() {
    pacman -Sl | pacman_format_all
}

pacman_format_installed() {
    awk "{ print $AS_NAME \$1 $AS_VERSION \$2 $AS_RESET }"
}

pacman_format_all() {
    awk "{ print $AS_NAME \$2 $AS_GROUP \$1 $AS_VERSION \$3 $AS_STATUS \$4 $AS_RESET }"
}

pacman_refresh() {
    sudo pacman -Sy
}

# =============================================================================
# Paru
# =============================================================================

paru_install() {
    paru -S --needed "$@"
}

paru_upgrade() {
    paru -Su
}

paru_remove() {
    paru -Rsc "$@"
}

paru_info() {
    paru -Si --color="$PM_COLOR" "$1"
}

paru_list_installed() {
    paru -Q | pacman_format_installed
}

paru_list_all() {
    # Unlike yay, this is fast enough and properly sorted
    paru -Sl | pacman_format_all
}

paru_refresh() {
    paru -Sy
}

# =============================================================================
# Yay
# =============================================================================

yay_install() {
    yay -S --needed "$@"
}

yay_upgrade() {
    yay -Su
}

yay_remove() {
    yay -Rsc "$@"
}

yay_info() {
    yay -Si --color="$PM_COLOR" "$1"
}

yay_list_installed() {
    yay -Q | pacman_format_installed
}

yay_list_all() {
    pacman_list_all
    yay -Sla | pacman_format_all
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
    # Using `apt show` is not recommended due to unstable CLI
    apt-cache show "$1"
}

apt_list_installed() {
    dpkg-query --show | awk "{ print $AS_NAME \$1 $AS_VERSION \$2 $AS_RESET }"
}

apt_list_all() {
    TMP=$(mktemp)
    dpkg-query --show -f '${package} [installed]\n' >"$TMP"
    apt-cache pkgnames |
        LC_ALL=C sort |
        join -j1 -a1 - "$TMP" |
        awk "{ print $AS_NAME \$1 $AS_STATUS \$2 $AS_RESET }"
    rm "$TMP"
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
    # Skip the first line which includes headers
    dnf info -q --color="$PM_COLOR" "$1" | tail -n+2
}

dnf_list_installed() {
    dnf repoquery -q --installed --qf '%{name} %{evr}' | awk "{ print $AS_NAME \$1 $AS_VERSION \$2 $AS_RESET }"
}

dnf_list_all() {
    TMP=$(mktemp)
    dnf repoquery -q --installed --qf '%{name} [installed]' >"$TMP"
    dnf repoquery -q --qf='%{name} %{repoid} %{evr}' |
        join -j1 -a1 - "$TMP" |
        awk "{ print $AS_NAME \$1 $AS_GROUP \$2 $AS_VERSION \$3 $AS_STATUS \$4 $AS_RESET }"
    rm "$TMP"
}

dnf_refresh() {
    sudo dnf check-update
}

# =============================================================================
# Run
# =============================================================================

main "$@"
