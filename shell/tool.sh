#!/bin/bash
# shellcheck disable=SC2086
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

    mapping="
        mongo 27017
        mysql 3306
        redis 6379
        pusher 64440
        messagesv 64441
        squaresv 64442
        edgesv 64443
        usersv 64444
        authsv 64445
        uploadsv 64446
        deliversv 64447
        usergrowthsv 64448
        riskcontrolsv 64449
        paysv 64450    
            "

    {
        # shellcheck disable=SC2317
        my_function() {
            while test $# -gt 0; do
                jspp-k8s-port-forward-simple "$1" "$2"
                shift
                shift
            done
        }
        # shellcheck disable=SC2086
        # shellcheck disable=SC2317
        my_function $mapping
    }
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
    echo "get log:               ./tool.sh [-s|--service-log cmd] [--service-log-pipe pipe]"
    echo "sync config:           ./tool.sh [--update-git-hook]"
    echo "show ip:               ./tool.sh [--iip]"
    echo "help:                  ./tool.sh [--help]"
    echo
}

args=$(getopt -o hs: -l "service-log:,service-log-pipe:,help,update-git-hook,iip,jspp-k8s-port-forward" -n "$0" -- "$@")
eval set -- "${args}"
echo "$args"
while true; do
    case "$1" in
    -s | --service-log)
        mapping="
        usersv
        mongo
        mysql
        redis
        pusher
        messagesv
        squaresv 
        edgesv
        authsv
        uploadsv
        deliversv
        usergrowthsv
        riskcontrolsv
        paysv"
        service="$2"
        my_function() {
            arr=()
            index=0
            while test $# -gt 0; do
                if [ "$service" = "$1" ]; then
                    arr[index]=$1
                    break
                fi
                shift
            done
            if [ ${#arr[@]} -eq 0 ]; then
                len=${#service}
                for ((i = 0; i < ${#service}; i++)); do
                    current=$(echo "$service" | cut -c 1-"$len")
                    for2() {
                        while test $# -gt 0; do
                            item=$(echo "$1" | cut -c 1-"$len")
                            if [ "$current" = "$item" ]; then
                                arr[index]=$1
                                index=$((index + 1))
                            fi
                            shift
                        done
                    }
                    for2 $mapping
                    if [ ${#arr[@]} -gt 0 ]; then
                        break
                    fi
                done
            fi
            for i in "${arr[@]}"; do
                echo "$i"
            done
        }
        my_function $mapping

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
    if [ "$service_pipe" != "" ]; then
        service-log "$service" "$service_pipe"
    else
        service-log "$service"
    fi
else
    echo
fi
