#!/usr/bin/env bash

# cp ../pushersv/.git/hooks/{commit-msg,pre-commit} .git/hooks

shopt -s expand_aliases
source ~/.bashrc

ViewLog() {
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
    echo "sub cmd:               ./tool.sh [[-c|--cmd|--command] cmd]"
    echo "help:                  ./tool.sh [-h|--help]"
    echo
}

args=$(getopt -o c:h --long help,cmd:,command: -- "$@")

if [ $? -ne 0 ]; then
    echo 'Usage: ...'
    exit 2
fi
eval set -- "$args"

while :; do
    case "$1" in
    -c | --cmd | --command)
        shift
        ViewLog $1
        shift
        ;;
    -h | --help)
        Help
        shift
        ;;
    --)
        shift
        break
        ;;
    esac
done