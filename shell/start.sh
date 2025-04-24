#!/usr/bin/env bash
SHELL_FOLDER=$(dirname $(readlink -f "$0"))
shopt -s expand_aliases
source /Users/jim/.bashrc
source "$SHELL_FOLDER"/libs/lib.sh
Main "$@"
