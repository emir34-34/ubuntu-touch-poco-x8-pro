#!/bin/bash

if [ -n "$TERM" ] && [ "$TERM" != "dumb" ]; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    POWDER_BLUE=$(tput setaf 153)
    RESET=$(tput sgr0)
fi

function print_error() {
    printf "${RED}%s${RESET}\\n" "${*}" 1>&2
}

function print_warning() {
    printf "${YELLOW}%s${RESET}\\n" "${*}"
}

function print_success() {
    printf "${GREEN}%s${RESET}\\n" "${*}"
}

function print_info() {
    printf "${POWDER_BLUE}%s${RESET}\\n" "${*}"
}

function print_message() {
    printf "${RESET}%s${RESET}\\n" "${*}"
}

function print_header() {
    printf "${GREEN}%s${RESET}\\n" "${*}"
}
