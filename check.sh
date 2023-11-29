#!/usr/bin/env sh

run() {
    if [ -x "$(command -v "$1")" ]; then
        "$@"
    else
        echo >&2 "$1 not found, install it using 'pm install $1'"
        exit 1
    fi
}

run shfmt -w pm
run shellcheck pm
