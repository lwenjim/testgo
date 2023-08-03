#! /bin/bash
# shellcheck disable=SC2086,SC2046
SHELL_FOLDER=$(dirname $(readlink -f "$0"))

shopt -s expand_aliases &>/tmp/a.log
source /Users/jim/.bashrc &>/tmp/a.log
source "$SHELL_FOLDER"/funcs.sh
main "$@"
