#!/usr/bin/env bash

# cp ../pushersv/.git/hooks/{commit-msg,pre-commit} .git/hooks

shopt -s expand_aliases
source ~/.bashrc

viewLog() {
    case $1 in
    usersv)
        app=usersv
        ;;
    messagesv)
        app=messagesv
        ;;
    momentsv)
        app=momentsv
        ;;
    pushersv)
        app=pushersv
        ;;
    esac
    if [ -n $app ]; then
        jspp-kubectl get pods | grep $app | awk -F'[ -]' '{print "jspp-kubectl logs -c "$1" --tail 1000 "$1"-"$2"-"$3}' | bash -i
    fi
}

Help() {
    echo "Automation Script"
    echo
    echo "Syntax: scriptTemplate [-m|h]"
    echo "options:"
    echo "m     actioin"
    echo "h     Print this Help."
    echo
}

ARGS=$(getopt -a -o log-view:,help -n "tool.sh" -- "$@")
echo $1
echo $2
[ $? -ne 0 ] && usage
set -- $args
while true; do
    case "$1" in
    -l|--log-view)
    echo $app
        app="$2"
        shift
        ;;
    -h | --help)
        Help
        ;;
    --)
        shift
        break
        ;;
    esac
    shift
done
echo $app
echo $@
# viewLog $app
