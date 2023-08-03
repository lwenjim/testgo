#! /bin/bash
# shellcheck disable=SC2086
SHELL_FOLDER=$(dirname $(readlink -f "$0"))
shopt -s expand_aliases
source /Users/jim/.bashrc

# source "$SHELL_FOLDER"/functions.sh
# service=
# service_pipe=
# service_option=
function service-log-pre() {
    local pattern="$1"
    local mapping="
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

    my_function() {
        local arr=()
        local index=0
        while test $# -gt 0; do
            if [ "$pattern" = "$1" ]; then
                arr[index]=$1
                break
            fi
            shift
        done
        if [ ${#arr[@]} -eq 0 ]; then
            local len=${#pattern}
            for ((i = 0; i < ${#pattern}; i++)); do
                local current=$(echo "$pattern" | cut -c 1-"$len")
                for2() {
                    while test $# -gt 0; do
                        local item=$(echo "$1" | cut -c 1-"$len")
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

        if [ ${#arr[@]} -eq 1 ]; then
            service=${arr[0]}
        else
            for i in "${arr[@]}"; do
                echo "$i"
            done
        fi
    }
    my_function $mapping
}

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
        my_function() {
            while test $# -gt 0; do
                jspp-k8s-port-forward-simple "$1" "$2"
                shift
                shift
            done
        }
        my_function $mapping
    }
}

function service-log() {
    local logParam='--tail 10 -f'
    if [ "$service_option" != "" ] && [ "$service_option" != "__" ]; then
        logParam=$(echo "$service_option" | tr -d '\')
    fi

    if [[ "usersv messagesv momentsv pushersv paysv authsv" == *"$service"* ]]; then
        local awkString=" awk -F'[ -]' "" '{print \"jspp-kubectl logs -c $service $logParam \"\$1\"-\"\$2\"-\"\$3}'"
        result=$(jspp-kubectl get pods | grep $service)
        result2=$(eval "echo $result|$awkString")
        if [ "$service_pipe" != "" ]; then
            echo "$result2  | $service_pipe" | bash -i
        else
            echo "$result2 " | bash -i
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
    echo "get log:               ./tool.sh [-s|--service-log cmd] [--service-log-pipe pipe] [--service-log-kubectl-logs-option option]"
    echo "sync config:           ./tool.sh [--update-git-hook]"
    echo "show ip:               ./tool.sh [--iip]"
    echo "help:                  ./tool.sh [--help]"
    echo
}

function main() {
    local args=$(getopt -o hs: -l "service-log:,service-log-pipe:,service-log-kubectl-logs-option:,help,update-git-hook,iip,jspp-k8s-port-forward" -n "$0" -- "$@" __)
    eval set -- "${args}"
    echo "$args"
    local pos=0
    while true; do
        case "$1" in
        -s | --service-log)
            service-log-pre "$2"
            shift
            shift
            ;;
        --service-log-pipe)
            service_pipe="$2"
            shift
            shift
            ;;
        --service-log-kubectl-logs-option)
            service_option="$2"
            shift
            shift
            ;;
        --)
            shift
            pos=$((pos + 1))
            ;;
        __)
            shift
            break
            ;;
        *)
            if [ $pos -eq 1 ]; then
                case "${1}" in
                "s")
                    service-log-pre "$2"
                    service_option="$3"
                    service_pipe="$4"
                    ;;
                *)
                    echo
                    ;;
                esac
                shift
            else
                cmd="${1//--/}"
                type "$cmd" &>/dev/null
                if [ $? ]; then
                    $cmd
                    shift
                else
                    exit
                fi
            fi
            ;;
        esac
    done

    if [ "$service" != "" ]; then
        service-log
    else
        echo
    fi
}
main "$@"
