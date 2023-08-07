#!/usr/bin/env bash
# shellcheck disable=SC2086,SC2046,1091
SHELL_FOLDER=$(dirname $(readlink -f "$0"))

shopt -s expand_aliases 
source /Users/jim/.bashrc
source "$SHELL_FOLDER"/funcs.sh
main "$@"
