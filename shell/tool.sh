#!/bin/bash
# shellcheck disable=SC2046
# SHELL_FOLDER=$(dirname $(readlink -f "$0"))
shopt -s expand_aliases

# shellcheck disable=SC1094
source /Users/jim/.bashrc
# source "$SHELL_FOLDER"/functions.sh

function jspp-k8s-port-forward-simple() {
    if [[ "mongo mysql redis" == *"${1}"* ]]; then
        name="${1}-0"
            jspp-kubectl port-forward "${name}" "${2}:${2}" >"/tmp/$1.log" 2>&1 &
    else
        name=$(jspp-kubectl get pods | grep "$1" | awk '{if(NR==1){print $1}}')
            jspp-kubectl port-forward "${name}" "${2}:9090" >"/tmp/$1.log" 2>&1 &
    fi

    if [ ! $? ]; then
        echo "$1 $name 启动失败"
    else
        echo "$1 $name 启动成功"
    fi
}

function jspp-k8s-port-forward() {
    ps aux | pgrep kube | awk '{print "kill -9 " $1}' | sudo bash

    jspp-k8s-port-forward-simple mongo 27017
    jspp-k8s-port-forward-simple mysql 3306
    jspp-k8s-port-forward-simple redis 6379

    jspp-k8s-port-forward-simple pusher 64440
    jspp-k8s-port-forward-simple messagesv 64441
    jspp-k8s-port-forward-simple squaresv 64442
    jspp-k8s-port-forward-simple edgesv 64443
    jspp-k8s-port-forward-simple usersv 64444
    jspp-k8s-port-forward-simple authsv 64445
    jspp-k8s-port-forward-simple uploadsv 64446
    jspp-k8s-port-forward-simple deliversv 64447
    jspp-k8s-port-forward-simple usergrowthsv 64448
    jspp-k8s-port-forward-simple riskcontrolsv 64449
    jspp-k8s-port-forward-simple paysv 64450
}

function service-log() {
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

function update-git-hook() {
    cd /Users/jim/Workdata/goland/src/jspp/pushersv || exit 1
    for item in usersv messagesv momentsv authsv deliversv edgesv groupsv pushersv uploadsv paysv; do
        cp -rf .git/hooks/{commit-msg,pre-commit} "../$item/.git/hooks"
    done
}

function iip() {
    ifconfig | grep "inet " | grep -v '127.0.0.1' | awk -F "inet" '{print $2}' | awk -F "netmask" '{print $1}' | tr -d " "
}

function help() {
    echo "Automation Script"
    echo
    echo "get log:               ./tool.sh [--service-log cmd] [--service-log-pipe pipe]"
    echo "sync config:           ./tool.sh [--update-git-hook]"
    echo "show ip:               ./tool.sh [--iip]"
    echo "help:                  ./tool.sh [--help]"
    echo
}

args=$(getopt -o h -l "service-log:,service-log-pipe:,help,update-git-hook,iip,jspp-k8s-port-forward" -n "$0" -- "$@")
eval set -- "${args}"
echo "$args"
while true; do
    case "$1" in
    --service-log)
        service="$2"
        shift
        shift
        ;;
    --service-log-pipe)
        service_pipe="$2"
        shift
        shift
        ;;
    --)
        shift
        break
        ;;
    *)
        cmd="${1//--/}"
        type "$cmd" &>/dev/null
        if [ $? ]; then
            $cmd
            shift
        else
            exit
        fi
        ;;
    esac
done

if [ "$service" != "" ]; then
    service-log "$service" "$service_pipe"
else
    echo
fi
