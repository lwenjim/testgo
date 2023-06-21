#!/usr/bin/env bash

shopt -s expand_aliases
source ~/.bashrc

ViewLog() {
    if [[ "usersv messagesv momentsv pushersv" == *"$1"* ]]; then
        jspp-kubectl get pods | grep $1 | awk -F'[ -]' '{print "jspp-kubectl logs -c "$1" --tail 1000 "$1"-"$2"-"$3}' | bash -i
    fi
}

UpdateHook() {
    cd /Users/jim/Workdata/goland/src/pushersv
    for item in usersv messagesv momentsv authsv deliversv edgesv groupsv pushersv uploadsv; do
        cp -rf .git/hooks/{commit-msg,pre-commit} "../$item/.git/hooks"
    done
}

Help() {
    echo "Automation Script"
    echo
    echo "get log:               ./tool.sh [-c|--command] cmd"
    echo "sync config:           ./tool.sh [-u|--update-hook]"
    echo "help:                  ./tool.sh [-h|--help]"
    echo
}

args=$(getopt -o uc:h --long update-hook,command,help: -- $*)

if [ $? -ne 0 ]; then
    Help
    exit 2
fi
eval set -- "$args"

while :; do
    case "$1" in
    -u | --update-hook)
        UpdateHook
        shift
        ;;
    -c | --command)
        shift
        ViewLog $1
        shift
        ;;
    -h | --help)
        Help
        shift
        ;;
    -- | *)
        break
        ;;
    esac
done