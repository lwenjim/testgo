#! /usr/bin/env bash
# shellcheck disable=SC2206,2068,2086,1091,2317,1090,2090,2089,2059,2046,2184

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
    ["groupsv"]=64454
)

debug=false

function sync-config() {
    cd ~ || exit 1
    cd $GO_JSPP_WORKSPACE || exit 1
    cd testgo || exit 1
    cp ~/.vimrc . \
    && cp ~/.bashrc . \
    && cp ~/.zshrc . \
    && cp ~/.bash_history . \
    && cp ~/.zsh_history . \
    && git add . \
    && git commit -m "update config $(date +"%Y-%m-%d %H:%I:%S")" \
    && git push
}

function main() {
    cmd="${1//--/}"
    if [ "$cmd" = "" ]; then
        help
    else
        if $cmd "$@"; then
            echo
        else
            echo  failed to executed or no exists for $cmd
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
    if [ "$service" = "" ]; then
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
    echo "$1" >/dev/null 2>&1
}

function port-forward() {
    arr=("$@")
    unset arr[0]

    ps aux | pgrep kube | awk '{print "kill -9 " $1}' | bash
    template="%-19s %-30s %-10s\n"
    printf "${template}" "服务名称" "环境变量" "    变量值"
    if [[ ${#arr[@]} -gt 0 ]];then
        for server in ${arr[@]}; do
            port-forward-simple "$server" "${ServiceServers[$server]}"
        done
    else
        for server in "${!ServiceServers[@]}"; do
            port-forward-simple "$server" "${ServiceServers[$server]}"
        done
    fi
    general-conf-for-nginx
    brew services reload openresty
}

function port-forward-simple() {
    if [[ "mongo mysql redis" == *"${1}"* ]]; then
        name="${1}-0"
        jspp-kubectl port-forward --address 0.0.0.0 "${name}" "${2}:${2}" >"/tmp/$1.log" 2>&1 &
    else
        name=$(jspp-kubectl get pods | grep "$1" | awk '{if(NR==1){print $1}}')
        if [[ "$name" == "" ]];then
            return 1
        else
            jspp-kubectl port-forward "${name}" "${2}:9090" >"/tmp/$1.log" 2>&1 &
        fi
    fi
    template="%-15s %-30s %-10s\n"
    if [ ! $? ]; then
        printf "${template}" "$1" "$name" "启动失败"
    else
        printf "${template}" "$1" "$name" "启动成功"
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
    echo -e "    get log:               a log usersv [-p | --pipe pipe] [-o | --option option]"
    echo -e "    sync config:           a update-git-hook"
    echo -e "    show env path:         a print-env-path"
    echo -e "    show env go:           a print-env-go"
    echo -e "    show env:              a print-env"
    echo -e "    forward port to local: a port-forward"
    echo -e "    show ip:               a ip"
    echo -e "    show help:             a help"
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
        access_log /tmp/aaaaaa-svc_nginx.log combined;

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

function print-env() {
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

function print-env-go() {
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

function workspace-gowork-sync() {
    filename=/tmp/go.work
    rm -f $filename >/dev/null 2>&1
    data=(
        internal-tools
        akita-go
        usersv
        testgo
    )
    {
        echo -e "go 1.21\n\nuse "
        echo "("
        for i in "${data[@]}"; do
            echo -e "\t../$i"
        done
        echo ")"
    } >>$filename
    for i in "${data[@]}"; do
        cp -f /tmp/go.work "$GOPATH/src/jspp/$i/go.work"
    done
    echo "sync go.work done"
}

function solitaire() {
    userQrcode=MAlHDK5Sg
    groupQrcode=O4W1DKcSg
    domain=https://devwww.jspp.com
    getinfoResp=$(curl --silent "$domain/solitaire/getinfo?user_qrcode=$userQrcode")
    echo $getinfoResp
    code=$(echo $getinfoResp | jq '.res')
    if [[ "$code" != "200" ]]; then
        echo "failed for /solitaire/getinfo"
        return
    fi

    addResp=$(curl --silent -d '
    {
        "title": "abc",
        "user_qrcode": "'$userQrcode'",
        "group_qrcode": "'$groupQrcode'",
        "content": [
            {
            "content": "abc"
            }
        ],
        "example": "abc",
        "extra_info": "abc"
    }' "$domain/solitaire/add")
    echo $addResp
    code=$(echo $addResp | jq '.res')
    if [[ "$code" != "200" ]]; then
        echo "failed for /solitaire/add"
        return
    fi
    topicQrcode=$(echo $addResp | jq '.data' | tr -d '"')

    detailResp=$(curl --silent "$domain/solitaire/detail?user_qrcode=$userQrcode&topic_qrcode=$topicQrcode")
    echo $detailResp
    code=$(echo $detailResp | jq '.res')
    if [[ "$code" != "200" ]]; then
        echo "failed for /solitaire/detail"
        return
    fi

    postResp=$(curl --silent -d '
        {
            "user_qrcode": "'$userQrcode'",
            "topic_qrcode": "'$topicQrcode'",
            "content": [
                {
                    "content": "'$(uuidgen)'"
                }
            ]
        }' "$domain/solitaire/post")
    echo $postResp
    code=$(echo $postResp | jq '.res')
    if [[ "$code" != "200" ]]; then
        echo "failed for /solitaire/post"
        return
    fi
}

function vote() {
    userQrcode=MAlHDK5Sg
    groupQrcode=O4W1DKcSg
    domain=https://devwww.jspp.com
    # domain=http://localhost:18083
    addResp=$(curl --silent -d '{
            "name": "'$(openssl rand -base64 8)'",
            "user_qrcode": "'$userQrcode'",
            "group_qrcode": "'$groupQrcode'",
            "end_time": '$(date -v+5d +"%s")',
            "is_multi_select": true,
            "is_anonymous": true,
            "option": [
                {
                    "name": "中国队",
                    "image": "https://img.jspp.com/xxx/xxx.png"
                },
                {
                    "name": "美国队",
                    "image": "https://img.jspp.com/xxx/xxx222.png"
                }
            ]
        }' $domain/vote/add)
    echo $addResp
    code=$(echo $addResp | jq '.res')
    if [[ "$code" != "200" ]]; then
        echo "failed for /vote/add"
        return
    fi
    topicQrcode=$(echo $addResp | jq '.data' | tr -d '"')

    listResp=$(curl -d '{"user_qrcode":"'$userQrcode'","group_qrcode":"'$groupQrcode'"}' --silent $domain/vote/list)
    echo $listResp
    code=$(echo $listResp | jq '.res')
    if [[ "$code" != "200" ]]; then
        echo "failed for /vote/list"
        return
    fi

    recordResp=$(curl --silent -d '
        {
            "user_qrcode": "'$userQrcode'",
            "topic_qrcode": "'$topicQrcode'"
        }' "$domain/vote/record")
    echo $recordResp
    code=$(echo $recordResp | jq '.res')
    if [[ "$code" != "200" ]]; then
        echo "failed for /vote/record"
        return
    fi

    postResp=$(curl --silent -d '
        {
            "user_qrcode": "'$userQrcode'",
            "topic_qrcode": "'$topicQrcode'",
            "option_id": [
                '$(echo $recordResp | jq ".data.options.[0].option.id")'
            ]
        }' "$domain/vote/post")
    echo $postResp
    code=$(echo $postResp | jq '.res')
    if [[ "$code" != "200" ]]; then
        echo "failed for /vote/post"
        return
    fi
}

function move-vsc-config() {
    echo "mv ~/.vscode-bak                                                             ~/.vscode"
    echo "mv ~/Library/Application\\ Support/Code-bak                                  ~/Library/Application\\ Support/Code"
    echo "mv ~/Library/Caches/com.microsoft.VSCode-bak                                 ~/Library/Caches/com.microsoft.VSCode"
    echo "mv ~/Library/Preferences/com.microsoft.VSCode.plist-bak                      ~/Library/Preferences/com.microsoft.VSCode.plist"
    echo "mv ~/Library/Saved\\ Application\\ State/com.microsoft.VSCode.savedState-bak ~/Library/Saved\\ Application\\ State/com.microsoft.VSCode.savedState"
}

dir=${SHELL_FOLDER}/handlers
list=$(ls $dir)
for i in ${list[@]} ; do
    source ${dir}/${i}
done
