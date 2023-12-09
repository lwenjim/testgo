#!/bin/bash
# shellcheck disable=SC2206 disable=SC2068 disable=SC2086 disable=SC1091 disable=SC2317 disable=SC1090 disable=SC2090 disable=SC2089 disable=SC2059

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
debug=false

function main() {
    cmd="${1//--/}"
    if [ "$cmd" = "" ]; then
        help
    else
        if $cmd "$@"; then
            echo
        else
            echo no exists for $cmd
        fi
    fi
}

function log() {
    option=
    service=$2
    pipe=
    param="
    o:,option:,
    p:,pipe:
    "
    if [ "$service" = "" ];then
        help
        return
    fi
    param=$(echo "$param" | tr -d '\n')
    args=$(getopt -o ho:p: -l "$param" -n "$0" -- "$@" __)
    eval set -- "${args}"
    while true; do
        case "$1" in
        -o | --option)
            option=$2
            shift
            shift
            ;;
        -p | --pipe)
            pipe=$2
            shift
            shift
            ;;
        --)
            shift
            ;;
        __ | *)
            shift
            break
            ;;
        esac
    done
    lprint $option
    lprint $pipe
    logOption='--tail 20'
    if [ "$option" != "" ]; then
        logOption=$(echo "$option" | tr -d "\\")
    fi

    for server in "${!ServiceServers[@]}"; do
        if [ "$server" != "$service" ]; then
            continue
        fi
        awkString=" awk -F'[ -]()' "" '{print \"jspp-kubectl logs -c $service $logOption \"\$1\"-\"\$2\"-\"\$3}'"
        lprint $awkString
        for i in $(jspp-kubectl get pods | grep "$service"); do
            result=$(echo "$i" | sed 's/(//' | sed 's/)//' | sed 's/\n\r//g')
            break
        done
        if [ "$result" = "" ]; then
            echo no launch for $service
            break
        fi
        lprint $result
        result2=$(eval "echo $result|$awkString")
        lprint $result2
        filename=/tmp/a.exe
        if [ "$pipe" != "" ]; then
            echo "$result2 | $pipe" >/tmp/a.exe
        else
            echo "$result2" >$filename
        fi
        source $filename
        break
    done
}

function lprint() {
    echo "$1" >/dev/null
}

function port-forward() {
    ps aux | pgrep kube | awk '{print "kill -9 " $1}' | sudo bash
    for server in "${!ServiceServers[@]}"; do
        port-forward-simple "$server" "${ServiceServers[$server]}"
    done
    general-conf-for-nginx
    brew services reload openresty
}

function port-forward-simple() {
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

function update-git-hook() {
    cd /Users/jim/Workdata/goland/src/jspp/pushersv >/dev/null 2>&1 || exit 1
    for forService in "${!ServiceServers[@]}"; do
        cd "../$forService" >/dev/null 2>&1 || continue
        cp -rf .git/hooks/{commit-msg,pre-commit} ".git/hooks" >/dev/null
    done
}

function ip() {
    ifconfig | grep "inet " | grep -v '127.0.0.1' | awk -F "inet" '{print $2}' | awk -F "netmask" '{print $1}' | tr -d " "
}

function help() {
    echo "Automation Script"
    echo
    echo "get log:               a log usersv [-p | --pipe pipe] [-o | --option option]"
    echo "sync config:           a update-git-hook"
    echo "show env path:         a print-env-path"
    echo "show env go:           a print-env-go"
    echo "show env:              a print-env"
    echo "forward port to local: a port-forward"
    echo "show ip:               a ip"
    echo "show help:             a help"
    echo
}

function general-conf-for-nginx() {
    declare -A DebugServers=(
        # ["authsv"]=19090
        # ["usersv"]=19091
        # ["paysv"]=19092
        # ["edgesv"]=19093
    )
    filename=~/servers/rpc.conf
    if [[ "$debug" = "false" ]]; then
        echo >$filename
    fi
    for server in "${!ServiceServers[@]}"; do
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

function print-env-path() {
    IFS=":"
    paths=(${PATH})
    noExists=()
    for i in "${paths[@]}"; do
        if [ "$i" = "" ]; then
            continue
        fi
        i=${i//\\/}
        if [ -d "$i" ]; then
            echo $i
        else
            noExists[${#noExists[@]}]=$i
        fi
    done
    echo
    echo
    for i in "${noExists[@]}"; do
        echo $i
    done
}

function print-env () {
    IFS=$'\n'
    data=$(env)
    arr=($data)
    template="%-40s %-10s\n"
    printf ${template} "环境变量" "    变量值"
    for variable in ${arr[@]}; do
        IFS="="
        item=($variable)
        if [ "${item[0]}" = "PATH" ] || [ "${item[1]}" = "" ]; then
            continue
        fi
        printf ${template} "${item[0]}" "${item[1]}"
    done
}

function print-env-go () {
    IFS=$'\n'
    data=$(go env)
    arr=($data)
    template="%-40s %-10s\n"
    printf ${template} "环境变量" "    变量值"
    for variable in ${arr[@]}; do
        IFS="="
        item=($variable)
        if [ "${item[0]}" = "PATH" ] || [ "${item[1]}" = "" ]; then
            continue
        fi
        printf ${template} "${item[0]}" "${item[1]}"
    done
}
