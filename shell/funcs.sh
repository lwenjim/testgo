#!/bin/bash
#shellcheck disable=SC2086,SC2046,SC2317,SC2155,SC2154,SC1003,2068,2206

# service=
# service_pipe=
# service_option=
declare -A ServiceServers=(
    ["mongo"]=27017
    ["mysql"]=3306
    ["redis"]=6379
    ["pushersv"]=64440
    ["messagesv"]=64441
    ["squaresv"]=64442
    ["edgesv"]=64443
    ["usersv"]=64444

    ["authsv"]=64445
    ["uploadsv"]=64446
    ["deliversv"]=64447
    ["usergrowthsv"]=64448
    ["riskcontrolsv"]=64449
    ["paysv"]=64450
    ["connectorsv"]=64451
    ["favoritesv"]=64452
    ["openapi"]=64453
)
cmdServers="
        update-git-hook
        jspp-k8s-port-forward
        iip
        help"
debug=false
function service-log-pre() {
    if [ "$1" = "" ]; then
        return 1
    fi
    local paramService="$1"
    local patternLen="${#paramService}"
    newServers=()
    for server in "${!ServiceServers[@]}"; do
        if [ ${#server} -ge $patternLen ]; then
            newServers[${#newServers[*]}]=$server
        fi
    done

    local resultServices=()
    for server1 in ${newServers[@]}; do
        if [ "$paramService" = "$server1" ]; then
            resultServices[${#resultServices[*]}]=$server1
            break
        fi
    done

    if [ ${#resultServices[@]} -eq 0 ]; then
        for ((strPos = ${#paramService}; strPos >= 1; strPos--)); do
            local partService=$(echo "$paramService" | cut -c 1-$strPos)
            for server2 in ${newServers[@]}; do
                local forService=$(echo "$server2" | cut -c 1-$strPos)
                if [ "$partService" = "$forService" ]; then
                    resultServices[${#resultServices[*]}]=$server2
                fi
            done
            if [ ${#resultServices[@]} -gt 0 ]; then
                break
            fi
        done
    fi

    if [ ${#resultServices[@]} -gt 0 ]; then
        if [ ${#resultServices[@]} -eq 1 ]; then
            service=${resultServices[0]}
        else
            for server in "${resultServices[@]}"; do
                echo "$server"
            done
        fi
    fi
}

function jspp-k8s-port-forward-simple() {
    if [[ "mongo mysql redis" == *"${1}"* ]]; then
        name="${1}-0"
        jspp-kubectl port-forward --address 0.0.0.0 "${name}" "${2}:${2}" >"/tmp/$1.log" 2>&1 &
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

    for server in "${!ServiceServers[@]}"; do
        jspp-k8s-port-forward-simple ${server} ${ServiceServers[$server]}
    done
}

function service-log() {
    local logParam='--tail 10 -f'
    if [ "$service_option" != "" ] && [ "$service_option" != "__" ]; then
        logParam=$(echo "$service_option" | tr -d '\')
    fi

    for server in "${!ServiceServers[@]}"; do
        if [ ${server} != $service ]; then
            continue
        fi
        local awkString=" awk -F'[ -]()' "" '{print \"jspp-kubectl logs -c $service $logParam \"\$1\"-\"\$2\"-\"\$3}'"
        result=$(jspp-kubectl get pods | grep $service | sed 's/(//' | sed 's/)//' | sed 's/\n\r//g')
        for i in $(jspp-kubectl get pods | grep $service); do
            result=$(echo $i | sed 's/(//' | sed 's/)//' | sed 's/\n\r//g')
            break
        done
        result2=$(eval "echo $result|$awkString")
        if [ "$service_pipe" != "" ]; then
            echo "$result2  | $service_pipe" | bash -i
        else
            echo "$result2 " | bash -i
        fi
    done
}

function update-git-hook() {
    cd /Users/jim/Workdata/goland/src/jspp/pushersv >/dev/null 2>&1 || exit 1
    for forService in "${!ServiceServers[@]}"; do
        cd "../$forService" >/dev/null 2>&1 || continue
        cd "../pushersv" >/dev/null 2>&1 || exit 1
        cp -rf .git/hooks/{commit-msg,pre-commit} "../$forService/.git/hooks"
    done
}

function iip() {
    ifconfig | grep "inet " | grep -v '127.0.0.1' | awk -F "inet" '{print $2}' | awk -F "netmask" '{print $1}' | tr -d " "
}

function help() {
    echo "Automation Script"
    echo
    echo "get log:               $0 [-s|--service-log cmd] [--service-log-pipe pipe] [--service-log-kubectl-logs-option option]"
    echo "sync config:           $0 [--update-git-hook]"
    echo "show ip:               $0 [--iip]"
    echo "help:                  $0 [--help]"
    echo
}

function sl() {
    if [ "$1" != "" ]; then
        if [ "$2" != "" ]; then
            $shell_path --service-log "$1" --service-log-pipe "\\""$2""\\"
        else
            $shell_path --service-log "$1"
        fi
    fi
}

function main() {
    param="
    service-log:,service-log-pipe:,service-log-kubectl-logs-option:,
    log:,log-pipe:,log-option:,
    help,update-git-hook,iip,jspp-k8s-port-forward
    "
    param=$(echo $param | tr -d '\n')
    local args=$(getopt -o hs: -l "$param" -n "$0" -- "$@" __)
    eval set -- "${args}"
    local pos=0
    while true; do
        case "$1" in
        -s | --service-log | --log)
            service-log-pre "$2"
            shift
            shift
            ;;
        --service-log-pipe | --log-pipe)
            service_pipe="$2"
            shift
            shift
            ;;
        --service-log-kubectl-logs-option | --log-option)
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
                case "$1" in
                "service")
                    service-log-pre "$2"
                    if [ "$3" != "" ] && [ "$3" != "__" ]; then
                        service_option="$3"
                    fi
                    if [ "$4" != "" ] && [ "$4" != "__" ]; then
                        service_pipe="$4"
                    fi
                    shift
                    shift
                    shift
                    ;;
                "update-git-hook")
                    update-git-hook
                    ;;
                "port-forward")
                    jspp-k8s-port-forward
                    general-conf-for-nginx
                    brew services reload openresty
                    ;;
                "iip")
                    iip
                    ;;
                *)
                    if [ "$1" != "" ]; then
                        service-log-pre "$1" "$cmdServers"
                        if [ "$service" != "" ]; then
                            $service
                        fi
                    else
                        break
                    fi
                    ;;
                esac
                shift
            else
                cmd="${1//--/}"
                type "$cmd" &>/dev/null
                if [ $? ]; then
                    $cmd "$@"
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

function general-conf-for-nginx() {
    declare -A DebugServers=(
        # ["edgesv"]=19093
        # ["usersv"]=19091
        # ["paysv"]=19092
        # ["authsv"]=19090
    )
    arr=(
        "pushersv"
        "messagesv"
        "squaresv"
        "edgesv"
        "usersv"
        "authsv"
        "uploadsv"
        "deliversv"
        "usergrowthsv"
        "riskcontrolsv"
        "paysv"
        "connectorsv"
        "favoritesv"
        "openapi"
    )
    filename=~/servers/rpc.conf
    if [[ "$debug" = "false" ]]; then
        echo >$filename
    fi
    for server in "${arr[@]}"; do
        if [ "$server" = 'mysql' ] || [ "$server" = "mongo" ] || [ "$server" = "redis" ]; then
            continue
        fi
        read -r -d '' template <<-'EOF'
    server {
        server_name aaaaaa-svc;
        listen 9090 http2;
        access_log /Users/jim/Workdata/wwwlogs/aaaaaa-svc_nginx.log combined;

        location / {
            grpc_pass grpc://127.0.0.1:77777;
        }
    }
EOF
        finded=false
        if [[ " ${!DebugServers[*]} " =~ $server ]]; then
            finded=true
        fi
        template="${template//aaaaaa/$server}"
        targetPort=${ServiceServers[$server]}
        if $finded; then
            targetPort=${DebugServers[$server]}
        fi
        template="${template//77777/$targetPort}"
        if [[ "$debug" = "false" ]]; then
            echo "$template" >>$filename
        else
            echo "$template"
        fi
    done
}
