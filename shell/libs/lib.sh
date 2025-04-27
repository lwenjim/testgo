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

ServiceServersOrder=(
    mongo
    mysql
    redis
    pushersv
    messagesv
    squaresv
    edgesv
    usersv
    authsv
    uploadsv
    deliversv
    usergrowthsv
    riskcontrolsv
    paysv
    connectorsv
    favoritesv
    openapi
    groupsv
)

debug=false

RemoveDuplicatePath() {
    gawk 'BEGIN{FixedPath()}'
}

UrlEncode() {
    shift
    if [[ $# == 0 ]];then
        return
    fi
    gawk 'BEGIN{print UrlEncode("'$1'")}'
}

UrlDecode() {
    shift
    if [[ $# == 0 ]];then
        return
    fi
    gawk 'BEGIN{print UrlDecode("'$1'")}'
}

ArrayIntersect() {
    arr=(${2//,/ })
    arr2=(${3//,/ })
    for out in ${arr[@]}; do
        for iin in ${arr2[@]}; do
            if [[ $out == $iin ]]; then
                echo $out
            fi
        done
    done
}

ArrayUnique() {
    shift
    declare -A res=()
    local data=($@)
    for item in ${data[@]//,/ }; do
        res[$item]=$item
    done
    for item in ${res[@]}; do
        echo $item
    done
}

SyncConfig() {
    cd ~ || exit 1
    cd $GO_JSPP_WORKSPACE || exit 1
    cd testgo || exit 1
    cp ~/.vimrc . &&
        cp ~/.bashrc . &&
        cp ~/.zshrc . &&
        git add . &&
        git commit -m "update config $(date +"%Y-%m-%d %H:%I:%S")" &&
        git push
}

Main() {
    Include "${SHELL_FOLDER}"/libs
    cmd="${1//--/}"
    if [[ ! -n $cmd ]]; then
        Help
    elif ! $cmd $@ 2>/tmp/a.log; then
        cat /tmp/a.log
    else
        echo
    fi
}

Log() {
    option=
    service=$2
    pipe=
    param="
    o:,option:,
    p:,pipe:
    "
    if [ "$service" = "" ]; then
        Help
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
    LogPrint $option
    LogPrint $pipe
    logOption='--tail 20'
    if [ "$option" != "" ]; then
        logOption=$(echo "$option" | tr -d "\\")
    fi
    for server in "${!ServiceServers[@]}"; do
        if [ "$server" != "$service" ]; then
            continue
        fi
        awkString=" awk -F'[ -]()' "" '{print \"jspp-kubectl logs -c $service $logOption \"\$1\"-\"\$2\"-\"\$3}'"
        LogPrint $awkString
        for i in $(jspp-kubectl get pods | grep "$service"); do
            result=$(echo "$i" | sed 's/(//' | sed 's/)//' | sed 's/\n\r//g')
            break
        done
        if [ "$result" = "" ]; then
            echo no launch for $service
            break
        fi
        LogPrint $result
        result2=$(eval "echo $result|$awkString")
        LogPrint $result2
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

LogPrint() {
    echo "$1" >/dev/null 2>&1
}

PortForward() {
    local arr=("$@")
    unset arr[0]

    ps aux | pgrep kube | awk '{print "kill -9 " $1}' | bash
    local template="%-5s %-19s %-30s %-10s\n"
    printf "${template}" "ID" "SERVICE NAME" "POD NAME" "STATUS"
    local index=1
    if [[ ${#arr[@]} -gt 0 ]]; then
        for server in ${arr[@]}; do
            PortForwardSimple "${server}" "${ServiceServers[$server]}" ${index}
            ((index++))
        done
        GeneralConfForNginx
        if ps -ef | grep nginx >/dev/null; then
            /usr/local/bin/openresty -s reload
        else
            brew services reload openresty
        fi
    else
        for server in "${ServiceServersOrder[@]}"; do
            PortForwardSimple "${server}" "${ServiceServers[$server]}" ${index}
            ((index++))
        done
    fi
}

PortForwardSimple() {
    if [[ "mongo mysql redis" == *"${1}"* ]]; then
        name="${1}-0"
        jspp-kubectl port-forward --address 0.0.0.0 "${name}" "${2}:${2}" >"/tmp/$1.log" 2>&1 &
    else
        name=$(jspp-kubectl get pods | grep "$1" | awk '{if(NR==1){print $1}}')
        if [[ "$name" == "" ]]; then
            return 1
        else
            jspp-kubectl port-forward "${name}" "${2}:9090" >"/tmp/$1.log" 2>&1 &
        fi
    fi
    local template="%-5s %-19s %-30s %-10s\n"
    if [ ! $? ]; then
        printf "${template}" ${index} "${1}" "${name}" "failed"
    else
        printf "${template}" ${index} "${1}" "${name}" "success"
    fi
}

UpdateGitHook() {
    cd $HOME/Workdata/goland/src/jspp/pushersv >/dev/null 2>&1 || exit 1
    for forService in "${!ServiceServers[@]}"; do
        cd "../$forService" >/dev/null 2>&1 || continue
        cp -rf .git/hooks/{commit-msg,pre-commit} ".git/hooks" >/dev/null
    done
}

IP() {
    ifconfig | grep "inet " | grep -v '127.0.0.1' | awk -F "inet" '{print $2}' | awk -F "netmask" '{print $1}' | tr -d " "
}

Help() {
    for item in $(List); do
        echo $item
    done
}

List() {
    for path in "${SHELL_FOLDER}"/libs/*.sh; do
        if [[ ! -f $path ]]; then
            continue
        fi
        cat $path | gawk '{
            match($0, /((function){0,1}[A-Z][A-Za-z]+)\(\)/, a);if (length(a[1])>0) print a[1]
        }'
    done
    echo
}

GeneralConfForNginx() {
    declare -A DebugServers=()
    filename=/usr/local/etc/openresty/servers/rpc.conf
    if [[ $debug ]]; then
        echo >$filename
    fi
    for server in "${!ServiceServers[@]}"; do
        if [[ "$server" = 'mysql' || "$server" = "mongo" || "$server" = "redis" ]]; then
            continue
        fi
        targetPort=${ServiceServers[$server]}
        if [[ " ${!DebugServers[*]} " =~ $server ]]; then
            targetPort=${DebugServers[$server]}
        fi
        read -r -d '' template <<EOF
        server {
            server_name $server-svc;
            listen 9090 http2;
            access_log /tmp/$server-svc_nginx.log combined;

            location / {
                grpc_pass grpc://127.0.0.1:$targetPort;
            }
        }
EOF
        if [[ $debug ]]; then
            echo "$template" >>$filename
        else
            echo "$template"
        fi
    done
}

PrintEnvPath() {
    IFS=":"
    paths=(${PATH})
    noExists=()
    for path in "${paths[@]}"; do
        if [ "$path" = "" ]; then
            continue
        fi
        path=${path//\\/}
        if [ -d "$path" ]; then
            echo $path
        else
            noExists[${#noExists[@]}]=$path
        fi
    done
    echo
    echo
    for path in "${noExists[@]}"; do
        echo $path
    done
}

PrintEnv() {
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

PrintEnvGo() {
    IFS=$'\n'
    data=$(go env)
    arr=($data)
    template="%-15s %-10s\n"
    printf ${template} "NAME" "VALUE"
    for variable in ${arr[@]}; do
        IFS="="
        item=($variable)
        if [ "${item[0]}" = "PATH" ] || [ "${item[1]}" = "" ]; then
            continue
        fi
        printf ${template} ${item[0]} ${item[1]}
    done
}

WorkspaceGoworkSync() {
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

MoveVscConfig() {
    echo "mv ~/.vscode-bak                                                             ~/.vscode"
    echo "mv ~/Library/Application\\ Support/Code-bak                                  ~/Library/Application\\ Support/Code"
    echo "mv ~/Library/Caches/com.microsoft.VSCode-bak                                 ~/Library/Caches/com.microsoft.VSCode"
    echo "mv ~/Library/Preferences/com.microsoft.VSCode.plist-bak                      ~/Library/Preferences/com.microsoft.VSCode.plist"
    echo "mv ~/Library/Saved\\ Application\\ State/com.microsoft.VSCode.savedState-bak ~/Library/Saved\\ Application\\ State/com.microsoft.VSCode.savedState"
}

CheckoutGoModSum() {
    cd $HOME/Workdata/goland/src/jspp || exit 1
    ll ./**/go.mod | awk -F' ' '{print $7}' | awk -F'/' '{print $1}' | xargs -I {} echo "cd {};git checkout go.mod go.sum" | xargs -I {} bash -c {}
}

CommitTimes() {
    commitTimes=/tmp/commitTimes.log
    author=hewen@jspp.cn
    echo "" >$commitTimes
    for server in "${!ServiceServers[@]}"; do
        cd $HOME/Workdata/goland/src/jspp/$server 2>/dev/null || continue
        git log --pretty='%aN' | sort | uniq -c | sort -k1 -n -r | head -n 3 1>>$commitTimes
    done

    echo "" >>$commitTimes
    cat $commitTimes | awk -F' ' '{ if($2 in num == 0) {num[$2]=0}; num[$2] += $1 } END{for(key in num){ if(num[key]==0) continue; else print key": ",num[key]", "}}' | xargs echo >>$commitTimes
    cat $commitTimes

    cat $commitTimes | awk -F' ' '{ if($2 in num == 0) {num[$2]=0}; num[$2] += $1 } END{for(key in num){ if(num[key]==0) continue; else if (key=="liuwenjin")print key"@jspp.com"; else print key"@jspp.cn"}}' | xargs -I {} bash -c 'source ~/.zshrc 2>/dev/null; a ChangeLineNum "$*"' _ {}
}

ChangeLineNum() {
    filename=/tmp/countLine.log
    author=$2
    echo "" >$filename
    for server in "${!ServiceServers[@]}"; do
        cd $HOME/Workdata/goland/src/jspp/$server 2>/dev/null || continue
        git log --author="$author" --pretty=tformat: --numstat | awk '{ add += $1; subs += $2; loc += $1 - $2 } END { if (add > 0) {printf "%s,%s,%s\n", add, subs, loc }}' - 1>>$filename
    done

    echo "" >>$filename
    data=$(cat $filename | awk -F',' '{ add += $1;subs += $2;loc += $3 } END { printf "added lines: %s, removed lines: %s, total lines: %s\n",add,subs,loc }')
    echo $author >>$filename
    echo $data >>$filename
    cat $filename
}

StockTrade() {
    echo $((6599 * 5 / 10 + 9600 * 2 / 10 + 400 * 5 + 300 * 3))
    echo
}

GoShell() {
    shift
    path=$HOME/Workdata/goland/src/jspp/
    cd $path || exit
    for item in $(ls $path); do
        case $item in
        "go.work.sum" | "go.work" | "testgo" | "pusher")
            continue
            ;;
        *) ;;
        esac
        if [[ "$item" == "testgo" ]]; then
            continue
        fi
        if [[ ! -d "$item" ]]; then
            continue
        fi
        cd $item || exit
        if [[ ! -f "go.mod" ]]; then
            cd ..
            continue
        fi
        removeFiles=("go.work" "go.work.sum" "go.work.bak")
        for item2 in "${removeFiles[@]}"; do
            if [[ -f "$item2" ]]; then
                rm -rf $item2
            fi
        done
        cmd=$*
        $cmd
        cd ..
    done
}

Include() {
    shopt -s globstar
    for path in "${SHELL_FOLDER}"/libs/**/*.sh; do
        if [[ $(basename $path) == "index.sh" ]]; then
            continue
        fi
        source $path
    done
    shopt -u globstar
}

rand() {
    if [[ "$1" == "" ]]; then
        return
    fi
    min=$1
    max=$((2 - min + 1))
    num=$((RANDOM + 1000000000))
    echo $((num % max + min))
}

UniquePATH() {
    export PATH=$(gawk 'BEGIN{UniquePATH()}')
}
