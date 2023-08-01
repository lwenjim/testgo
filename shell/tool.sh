#!/bin/bash

shopt -s expand_aliases

source /Users/jim/.bashrc

ViewLog() {
    service="$1"
    pipe="$2"
    if [[ "usersv messagesv momentsv pushersv paysv authsv" == *"${service}"* ]]; then
        result=$(jspp-kubectl get pods | grep "${service}" | awk -F'[ -]' '{print "jspp-kubectl logs -c "$1" --tail 1000 -f "$1"-"$2"-"$3}')
        if [ "${pipe}" != "" ]; then
            echo "${result}|${pipe}" | bash -i
        else
            jspp-kubectl get pods | grep "${service}" | awk -F'[ -]' '{print "jspp-kubectl logs -c "$1" --tail 1000 -f "$1"-"$2"-"$3}' | bash -i
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
    echo "get log:               ./tool.sh [-c|--show-log cmd] [--show-log-pipe pipe]"
    echo "sync config:           ./tool.sh [-u|--update-git-hook]"
    echo "help:                  ./tool.sh [-h|--help]"
    echo
}

update_git_hook=
help=
service=
service_pipe=

args=$(getopt -o uc:hv: -l update-git-hook,service:,help,service-pipe: -n "$0" --  "$@")
eval set -- "${args}"
echo "$args"
while true; do
    case "$1" in
    -u | --update-git-hook)
        update_git_hook=true
        shift
        ;;
    -c | --service)
        service="$2"
        shift
        shift
        ;;
    -v | --service-pipe)
        service_pipe="$2"
        shift
        shift
        ;;
    -h | --help)
        help=true
        shift
        ;;
    --)
        shift
        break
        ;;
    *)
        exit
        ;;
    esac
done

if [ "$update_git_hook" != "" ]; then
    UpdateHook
elif [ "$service" != "" ]; then
    echo ViewLog "$service" "$service_pipe"
elif [ "$help" != "" ]; then
    Help
else
    echo
fi
