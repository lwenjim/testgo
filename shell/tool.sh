#!/usr/bin/env bash

shopt -s expand_aliases

# shellcheck source=/dev/null
source /Users/jim/.bashrc

ViewLog() {
    if [[ "usersv messagesv momentsv pushersv paysv authsv" == *"$1"* ]]; then
        result=$(jspp-kubectl get pods | grep "$1" | awk -F'[ -]' '{print "jspp-kubectl logs -c "$1" --tail 1000 -f "$1"-"$2"-"$3}')
        if [ "$2" != "" ]; then
            echo "${result}|$2" | bash -i
        else
            jspp-kubectl get pods | grep "$1" | awk -F'[ -]' '{print "jspp-kubectl logs -c "$1" --tail 1000 -f "$1"-"$2"-"$3}' | bash -i
        fi
    fi
}

UpdateHook() {
    cd /Users/jim/Workdata/goland/src/pushersv || exit 1
    for item in usersv messagesv momentsv authsv deliversv edgesv groupsv pushersv uploadsv paysv; do
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

update_hook=false
help=false
view_log=""
view_log_sub=""
args=$(getopt -o uc:h:v --long update-hook,view-log,help,view-sub -- "$@")
eval set -- "$args"

while :; do
    case "$1" in
    -u | --update-hook)
        update_hook=true
        shift
        ;;
    -c | --view-log)
        shift
        view_log="$1"
        shift
        ;;
    -v | --view-sub)
        shift
        view_log_sub="$1"
        echo "$1"
        shift
        ;;
    -h | --help)
        help=true
        shift
        ;;
    -- | *)
        break
        ;;
    esac
done

if [ "$update_hook" = true ]; then
    UpdateHook
elif [ "$view_log" != "" ]; then
    # ViewLog "$view_log" "$view_log_sub"
    echo "$view_log_sub"
elif [ "$help" != "" ]; then
    Help
fi
