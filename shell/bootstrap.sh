#!/usr/bin/env bash
# SHELL_FOLDER=$(dirname $(readlink -f "$0"))
SHELL_FOLDER=/Users/jim/Workdata/goland/src/jspp/testgo/shell
shopt -s expand_aliases
source /Users/jim/.bashrc
source "$SHELL_FOLDER"/index.sh
main "$@"
