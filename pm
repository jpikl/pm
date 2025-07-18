#!/usr/bin/env sh

# shellcheck disable=SC2064

set -eu

export LC_ALL=C

usage() {
    echo "Package manager wrapper (supports: $PMS)"
    echo
    echo "Usage: $0 <command>"
    echo
    echo "Commands:"
    echo "  i,  install          Interactively select packages to install."
    echo "  i,  install <pkg>... Install one or more packages."
    echo "  r,  remove           Interactively select packages to remove."
    echo "  r,  remove <pkg>...  Remove one or more packages."
    echo "  u,  upgrade          Upgrade all installed packages."
    echo "  f,  fetch            Update local package database."
    echo "  n,  info <pkg>       Print package information."
    echo "  la, list all         List all packages."
    echo "  li, list installed   List installed packages."
    echo "  sa  search all       Interactively search between all packages."
    echo "  si  search installed Interactively search between installed packages."
    echo "  w,  which            Print which package manager is being used."
    echo "  h,  help             Print this help."
    echo
    echo "Interactive commands can read additional filters from standard input."
    echo "Each line is a regular expression (POSIX extended), matching whole package name."
}

main() {
    if [ $# -eq 0 ]; then
        die_wrong_usage "expected <command> argument"
    fi

    if [ "$1" = h ] || [ "$1" = -h ] || [ "$1" = help ] || [ "$1" = --help ]; then
        usage
        exit
    fi

    if [ ! "${PM_COLOR+is_set}" ]; then
        if [ -t 1 ]; then
            PM_COLOR="always"
        else
            PM_COLOR="never"
        fi
    fi

    if [ ! "${PM_SUDO+is_set}" ]; then
        PM_SUDO=
        # Termux package installation does not require sudo
        if [ ! "${TERMUX_VERSION-}" ]; then
            for NAME in sudo sudo-rs doas; do
                if is_command "$NAME"; then
                    PM_SUDO="$NAME"
                    break
                fi
            done
        fi
    fi

    # We cannot pass empty sudo command option to AUR helpers, so we use `env` as workaround.
    AUR_SUDO=${PM_SUDO:-env}

    # Output formatting
    if [ "$PM_COLOR" = always ]; then
        FMT_NAME='"\033[1m"'
        FMT_GROUP='" \033[1;35m"'
        FMT_VERSION='" \033[1;36m"'
        FMT_STATUS='" \033[1;32m"'
        FMT_RESET='"\033[0m"'
    else
        FMT_NAME='""'
        FMT_GROUP='" "'
        FMT_VERSION='" "'
        FMT_STATUS='" "'
        FMT_RESET='""'
    fi

    pm_detect

    PM_CACHE_DIR=${XDG_CACHE_DIR:-$HOME/.cache}/pm/$PM
    mkdir -p "$PM_CACHE_DIR"

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
    f | fetch) fetch ;;
    w | which) which ;;
    *) die_wrong_usage "invalid <command> argument '$COMMAND'" ;;
    esac
}

# =============================================================================
# Commands
# =============================================================================

install() {
    if [ ! -f "$PM_CACHE_DIR/last-fetch" ] || [ "$(cat "$PM_CACHE_DIR/last-fetch")" != "$(current_date)" ]; then
        pm_fetch
    fi
    if [ $# -eq 0 ]; then
        search all | PM=$PM PM_COLOR=$PM_COLOR xargs_self install
    else
        pm_install "$@"
    fi
}

remove() {
    if [ $# -eq 0 ]; then
        search installed | PM=$PM PM_COLOR=$PM_COLOR xargs_self remove
    else
        pm_remove "$@"
    fi
}

upgrade() {
    pm_fetch
    pm_upgrade
}

fetch() {
    pm_fetch
}

info() {
    pm_info "$1"
}

list() {
    check_source "$@"
    pm_list "$1" | pm_format "$1"
}

search() {
    check_source "$@"

    if [ -t 0 ]; then
        pm_list "$1" | pm_format "$1" | interactive_filter
    else
        FILTER_FILE=$(mktemp)
        trap "rm -f -- '$FILTER_FILE'" EXIT
        compile_stdin_filter >"$FILTER_FILE"
        pm_list "$1" | grep -Ef "$FILTER_FILE" | pm_format "$1" | interactive_filter
    fi
}

which() {
    echo "$PM"
}

# =============================================================================
# Utils
# =============================================================================

die() {
    echo >&2 "$0: $1"
    exit 1
}

die_wrong_usage() {
    die "$1, run '$0 help' for usage"
}

is_command() {
    [ -x "$(command -v "$1")" ]
}

current_date() {
    date -u +%Y-%m-%d
}

check_source() {
    if [ $# -eq 0 ]; then
        die_wrong_usage "expected <source> argument"
    elif [ "$1" != installed ] && [ "$1" != all ]; then
        die_wrong_usage "invalid <source> argument '$1'"
    fi
}

compile_stdin_filter() {
    # 1. Remove comments '#...'
    # 2. Trim lines
    # 3. Remove empty lines
    # 4. Insert matching context ("start of line" ... "end of line" or "whitespace")
    sed -E 's/#.*//;s/^\s+//;s/\s+$//' |
        { grep . || die "empty stdin filter"; } |
        awk '{ print "^" $1 "($|\\s)" }'
}

interactive_filter() {
    if [ ! "${COLUMNS-}" ] && is_command tput; then
        COLUMNS=$(tput cols)
    fi

    if [ "${COLUMNS:-80}" -lt 80 ]; then
        PREVIEW_WINDOW='down:50%'
    else
        PREVIEW_WINDOW='right:50%'
    fi

    if is_command fzf; then
        fzf --exit-0 \
            --multi \
            --no-sort \
            --ansi \
            --layout=reverse \
            --exact \
            --cycle \
            --preview="PM=$PM PM_COLOR=$PM_COLOR $0 info {1}" \
            --preview-window "$PREVIEW_WINDOW" |
            cut -d" " -f1
    else
        die "fzf is not available, run '$0 install fzf' first"
    fi
}

skip_table_header() {
    while read -r LINE; do
        case "$LINE" in
        --*) cat ;;
        esac
    done
}

xargs_self() {
    # Some older xargs implementations (busybox < 1.36) do not support `-o` option to reopen /dev/tty as stdin.
    # This is a workaround suggested by `man xargs`.
    # shellcheck disable=SC2016
    xargs -r sh -c '"$0" "$@" </dev/tty' "$0" "$@"
}

with_sudo() {
    if [ "$PM_SUDO" ]; then
        "$PM_SUDO" "$@"
    else
        "$@"
    fi
}

# =============================================================================
# PM wrapper
# =============================================================================

# Package managers are detected in this order
PMS="paru yay pacman apt dnf zypper apk brew scoop"

pm_detect() {
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
}

pm_install() {
    "${PM}_install" "$@"
}

pm_remove() {
    "${PM}_remove" "$@"
}

pm_upgrade() {
    "${PM}_upgrade"
}

pm_fetch() {
    "${PM}_fetch"
    current_date >"$PM_CACHE_DIR/last-fetch"
}

pm_info() {
    "${PM}_info" "$1"
}

pm_list() {
    "${PM}_list_$1"
}

pm_format() {
    "${PM}_format_$1"
}

# =============================================================================
# Pacman
# =============================================================================

pacman_install() {
    for PKG in "$@"; do
        if aur_helpers_contain "$PKG"; then
            # Custom install procedure for AUR helpers
            aur_helpers_install "$PKG"
            # Re-run the installation for the remaining packages (should use the installed helper as PM)
            printf "%s\n" "$@" | grep -Fv "$PKG" | xargs_self install
            return
        fi
    done
    with_sudo pacman -S --needed "$@"
}

pacman_remove() {
    with_sudo pacman -Rsc "$@"
}

pacman_upgrade() {
    with_sudo pacman -Su
}

pacman_fetch() {
    with_sudo pacman -Sy
}

pacman_info() {
    if aur_helpers_contain "$1"; then
        aur_helpers_info "$1"
    else
        pacman -Si --color="$PM_COLOR" "$1"
    fi
}

pacman_list_all() {
    pacman -Sl --color=never | awk '{ print $2 " " $1 " " $3 " " $4 }'
    aur_helpers_list
}

pacman_list_installed() {
    pacman -Q --color=never
}

pacman_format_all() {
    awk "{ print $FMT_NAME \$1 $FMT_GROUP \$2 $FMT_VERSION \$3 $FMT_STATUS \$4 $FMT_RESET }"
}

pacman_format_installed() {
    awk "{ print $FMT_NAME \$1 $FMT_VERSION \$2 $FMT_RESET }"
}

# =============================================================================
# AUR helpers
# =============================================================================

AUR_HELPERS="paru paru-bin yay yay-bin"

aur_helpers_contain() {
    for NAME in $AUR_HELPERS; do
        if [ "$1" = "$NAME" ]; then
            return 0
        fi
    done
    return 1
}

aur_helpers_install() {
    with_sudo pacman -S --needed git base-devel
    AUR_DIR=$(mktemp -d)
    trap "rm -rf -- '$AUR_DIR'" EXIT
    git clone "https://aur.archlinux.org/$1.git" "$AUR_DIR"
    cd "$AUR_DIR"
    makepkg -si
}

aur_helpers_info() {
    printf "\e[1mRepository  :\e[0m aur\n"
    printf "\e[1mName        :\e[0m %s\n" "$1"
    printf "\e[1mDescription :\e[0m AUR helper\n"
}

aur_helpers_list() {
    # shellcheck disable=SC2086
    printf "%s aur\n" $AUR_HELPERS
}

# =============================================================================
# Paru
# =============================================================================

paru_install() {
    paru --sudo "$AUR_SUDO" -S --needed "$@"
}

paru_remove() {
    paru --sudo "$AUR_SUDO" -Rsc "$@"
}

paru_upgrade() {
    paru --sudo "$AUR_SUDO" -Su
}

paru_fetch() {
    paru --sudo "$AUR_SUDO" -Sy
}

paru_info() {
    paru -Si --color="$PM_COLOR" "$1"
}

paru_list_all() {
    paru -Sl --color=never | awk '{ print $2 " " $1 " " $3 " " $4 }'
}

paru_list_installed() {
    paru -Q --color=never
}

paru_format_all() {
    awk "{ print $FMT_NAME \$1 $FMT_GROUP \$2 $FMT_VERSION \$3 $FMT_STATUS \$4 $FMT_RESET }"
}

paru_format_installed() {
    awk "{ print $FMT_NAME \$1 $FMT_VERSION \$2 $FMT_RESET }"
}

# =============================================================================
# Yay
# =============================================================================

yay_install() {
    yay --sudo "$AUR_SUDO" -S --needed "$@"
}

yay_remove() {
    yay --sudo "$AUR_SUDO" -Rsc "$@"
}

yay_upgrade() {
    yay --sudo "$AUR_SUDO" -Su
}

yay_fetch() {
    yay --sudo "$AUR_SUDO" -Sy
}

yay_info() {
    yay -Si --color="$PM_COLOR" "$1"
}

yay_list_all() {
    # We want non-AUR results first and pacman is also much faster than yay here.
    {
        pacman -Sl --color=never
        yay -Sla --color=never
    } | awk '{ print $2 " " $1 " " $3 " " $4 }'
}

yay_list_installed() {
    yay -Q --color=never
}

yay_format_all() {
    awk "{ print $FMT_NAME \$1 $FMT_GROUP \$2 $FMT_VERSION \$3 $FMT_STATUS \$4 $FMT_RESET }"
}

yay_format_installed() {
    awk "{ print $FMT_NAME \$1 $FMT_VERSION \$2 $FMT_RESET }"
}

# =============================================================================
# Apt
# =============================================================================

apt_install() {
    with_sudo apt install "$@"
}

apt_remove() {
    with_sudo apt remove "$@"
}

apt_upgrade() {
    with_sudo apt upgrade
}

apt_fetch() {
    with_sudo apt update
}

apt_info() {
    # Using `apt show` is not recommended due to unstable CLI
    apt-cache show "$1"
}

apt_list_all() {
    INSTALLED_PKGS_FILE=$(mktemp)
    trap "rm -f -- '$INSTALLED_PKGS_FILE'" EXIT
    dpkg-query --show -f '${package} [installed]\n' >"$INSTALLED_PKGS_FILE"
    apt-cache pkgnames | sort | join -j1 -a1 - "$INSTALLED_PKGS_FILE"
}

apt_list_installed() {
    dpkg-query --show
}

apt_format_all() {
    awk "{ print $FMT_NAME \$1 $FMT_STATUS \$2 $FMT_RESET }"
}

apt_format_installed() {
    awk "{ print $FMT_NAME \$1 $FMT_VERSION \$2 $FMT_RESET }"
}

# =============================================================================
# Dnf
# =============================================================================

dnf_install() {
    with_sudo dnf install "$@"
}

dnf_remove() {
    with_sudo dnf remove "$@"
}

dnf_fetch() {
    # dnf exists with code 100 in distrobox https://github.com/fedora-cloud/docker-brew-fedora/issues/46
    with_sudo dnf check-update || true
}

dnf_upgrade() {
    with_sudo dnf upgrade
}

dnf_info() {
    # Skip the first header line
    dnf info -q --color="$PM_COLOR" "$1" | grep :
}

dnf_list_all() {
    INSTALLED_PKGS_FILE=$(mktemp)
    trap "rm -f -- '$INSTALLED_PKGS_FILE'" EXIT
    dnf repoquery -q --installed --qf '%{name} [installed]' >"$INSTALLED_PKGS_FILE"
    dnf repoquery -q --qf='%{name} %{repoid} %{evr}' | join -j1 -a1 - "$INSTALLED_PKGS_FILE"
}

dnf_list_installed() {
    dnf repoquery -q --installed --qf '%{name} %{evr}'
}

dnf_format_all() {
    awk "{ print $FMT_NAME \$1 $FMT_GROUP \$2 $FMT_VERSION \$3 $FMT_STATUS \$4 $FMT_RESET }"
}

dnf_format_installed() {
    awk "{ print $FMT_NAME \$1 $FMT_VERSION \$2 $FMT_RESET }"
}

# =============================================================================
# Zypper
# =============================================================================

zypper_install() {
    # Confirmation after interactive package selection does not work (user input from stdin is not read)
    with_sudo zypper install --no-confirm "$@"
}

zypper_remove() {
    # Confirmation after interactive package selection does not work (user input from stdin is not read)
    with_sudo zypper remove --no-confirm "$@"
}

zypper_fetch() {
    with_sudo zypper refresh
}

zypper_upgrade() {
    with_sudo zypper update
}

zypper_info() {
    zypper info "$1" | skip_table_header
}

zypper_list_all() {
    zypper packages --sort-by-name | skip_table_header | awk 'BEGIN { FS = "|" } ; { if (substr($1, 0, 1) == "i") print $3 $2 $4 "[installed]"; else print $3 $2 $4 }'
}

zypper_list_installed() {
    # Filter out duplicated entries with alternate version available (lines starting with 'v' status)
    zypper packages --sort-by-name --installed-only | skip_table_header | grep -v '^v' | awk 'BEGIN { FS = "|" } ; { print $3 $2 $4 }'
}

zypper_format_all() {
    awk "{ print $FMT_NAME \$1 $FMT_GROUP \$2 $FMT_VERSION \$3 $FMT_STATUS \$4 $FMT_RESET }"
}

zypper_format_installed() {
    awk "{ print $FMT_NAME \$1 $FMT_GROUP \$2 $FMT_VERSION \$3 $FMT_RESET }"
}

# =============================================================================
# APK
# =============================================================================

apk_install() {
    with_sudo apk add "$@"
}

apk_remove() {
    with_sudo apk del "$@"
}

apk_fetch() {
    with_sudo apk update
}

apk_upgrade() {
    with_sudo apk upgrade
}

apk_info() {
    apk info "$1"
}

apk_list_all() {
    # First `sed` splits the version from package name `zlib-1.3.1-r0` -> `zlib 1.3.1-r0`
    # Seconds `sed` removes license `(...)` like `(BSD-3-Clause AND Apache-2.0 AND MIT)` to get rid of problematic whitespaces
    apk list --available | sed -E 's/-(\d)/ \1/;s/\([^)]+\)//' | awk '{ print $1 " " $4 " " $2 " " $5 }'
}

apk_list_installed() {
    # `sed` splits the version from package name `zlib-1.3.1-r0` -> `zlib 1.3.1-r0`
    apk list --installed | sed -E 's/-(\d)/ \1/' | awk '{ print $1 " " $4 " " $2 }'
}

apk_format_all() {
    awk "{ print $FMT_NAME \$1 $FMT_GROUP \$2 $FMT_VERSION \$3 $FMT_STATUS \$4 $FMT_RESET }"
}

apk_format_installed() {
    awk "{ print $FMT_NAME \$1 $FMT_GROUP \$2 $FMT_VERSION \$3 $FMT_RESET }"
}

# =============================================================================
# Brew
# =============================================================================

brew_install() {
    brew install "$@"
}

brew_remove() {
    brew uninstall "$@"
}

brew_fetch() {
    brew update
}

brew_upgrade() {
    brew upgrade
}

brew_info() {
    [ "$PM_COLOR" = always ] && export HOMEBREW_COLOR=1
    brew info "$1"
}

brew_list_all() {
    INSTALLED_PKGS_FILE=$(mktemp)
    trap "rm -f -- '$INSTALLED_PKGS_FILE'" EXIT
    brew list -1 | awk '{ print $1 " [installed]" }' >"$INSTALLED_PKGS_FILE"
    {
        brew formulae
        [ "$(uname -s)" = Darwin ] && brew casks
    } | grep . | sort -u | join -j1 -a1 - "$INSTALLED_PKGS_FILE"
}

brew_list_installed() {
    brew list -1
}

brew_format_all() {
    awk "{ print $FMT_NAME \$1 $FMT_STATUS \$2 $FMT_RESET }"
}

brew_format_installed() {
    awk "{ print $FMT_NAME \$1 $FMT_RESET }"
}

# =============================================================================
# Scoop
# =============================================================================

scoop_install() {
    scoop install "$@"
}

scoop_remove() {
    scoop uninstall "$@"
}

scoop_fetch() {
    # Scoop search is very slow (especialy with multiple buckets) so we do create our own cache
    echo >&2 "Fetching packages..."
    scoop search | skip_table_header | grep . | awk '{ print $1 " " $3 " " $2 }' | sort >"$PM_CACHE_DIR/packages"
}

scoop_upgrade() {
    scoop update
}

scoop_info() {
    scoop info "$1" | grep .
}

scoop_list_all() {
    INSTALLED_PKGS_FILE=$(mktemp)
    trap "rm -f -- '$INSTALLED_PKGS_FILE'" EXIT
    scoop list | skip_table_header | grep . | awk '{ print $1 " [installed]" }' >"$INSTALLED_PKGS_FILE"
    [ -f "$PM_CACHE_DIR/packages" ] || scoop_fetch
    join -j1 -a1 "$PM_CACHE_DIR/packages" "$INSTALLED_PKGS_FILE"

}

scoop_list_installed() {
    scoop list | skip_table_header | grep . | awk '{ print $1 " " $3 " " $2 }'
}

scoop_format_all() {
    awk "{ print $FMT_NAME \$1 $FMT_GROUP \$2 $FMT_VERSION \$3 $FMT_STATUS \$4 $FMT_RESET }"
}

scoop_format_installed() {
    awk "{ print $FMT_NAME \$1 $FMT_GROUP \$2 $FMT_VERSION \$3 $FMT_RESET }"
}

# =============================================================================
# Run
# =============================================================================

main "$@"
