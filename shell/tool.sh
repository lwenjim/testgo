#!/usr/bin/env bash

# cp ../pushersv/.git/hooks/{commit-msg,pre-commit} .git/hooks

shopt -s expand_aliases

source ~/.bashrc

Do() {
    case $1 in
    usersv)
        app=usersv
        ;;
    messagesv)
        app=messagesv
        ;;
    esac
    if [ -n $app ]; then
        jspp-kubectl get pods | grep $app | awk -F'[ -]' '{print "jspp-kubectl logs -c "$1" --tail 1000 "$1"-"$2"-"$3}' | bash -i
    fi
}

Help() {
    echo "Add description of the script functions here."
    echo
    echo "Syntax: scriptTemplate [-g|h|v|V]"
    echo "options:"
    echo "l     call kubectl return log"
    echo "h     Print this Help."
    echo "v     Verbose mode."
    echo "V     Print software version and exit."
    echo
}

while getopts "l:h" option; do
    case $option in
    l)
        echo
        Do $OPTARG
        ;;
    h)
        Help
        ;;
    esac
done
