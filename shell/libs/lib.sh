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
	["momentsv"]=64455
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
	momentsv
)

debug=false

CheckoutAllForce() {
	local path=~/Workdata/goland/src/jspp
	if [[ ! -d $path ]]; then
		echo "not exists "$path
		return
	fi
	cur=$(pwd)
	cd $path
	for item in *; do
		if [ -f $path/$item ]; then
			continue
		fi
		if [ ! -d $path/$item/.git/hooks ]; then
			continue
		fi
		cd $item || exit 2
		echo $item
		for branch in develop master; do
			git co $branch
			git pull
		done
		cd ..
	done
	cd $cur
}

CheckoutAll() {
	local path=~/Workdata/goland/src/jspp
	if [[ ! -d $path ]]; then
		echo "not exists "$path
		return
	fi
	for item in ${ServiceServersOrder[@]}; do
		if [[ -d "$path/$item" ]]; then
			echo "exists "$path/$item
			continue
		fi
		git clone git@code.jspp.com:jspp/$item.git
	done
}

ClearMysqlGenerateLog() {
	echo 123
}

PullAll() {
	cd $GOPATH/src/jspp/testgo || exit 131
	for i in $(ls ..); do
		cd ../$i || exit 131
		if [ ! -f .git/config ]; then
			continue
		fi
		if [ $(git status -s | wc -l) == "1" ]; then
			continue
		fi
		git pull
	done
}

loadnvm() {
	source $(brew --prefix)/opt/nvm/nvm.sh
	source $(brew --prefix)/opt/nvm/etc/bash_completion.d/nvm
}

mysqleval() {
	shift
	mysql -uroot -P3306 -p123456789 -h127.0.0.1 jspp -e "${*/\\*/*}"
}

Co() {
	shift
	local branchName=$1
	shift
	if [[ "" == "$*" ]]; then
		return
	fi

	local isChange=
	for item in $@; do
		if [ ! -d $GOPATH/src/jspp/$item ]; then
			echo not exists $item
			isChange=on
			continue
		fi
		cd $GOPATH/src/jspp/$item || exit 131
		if [[ $(git status --short 2>/dev/null) != "" ]]; then
			isChange=on
			echo $item:
			git status --short 2>/dev/null
			echo
		fi
	done

	if [[ $isChange != "" ]]; then
		return
	fi
	local index=1
	for item in $@; do
		cd $GOPATH/src/jspp/$item || continue
		if git co $branchName >/dev/null 2>&1; then
			printf "%d %-20s %-30s\n" $index $item $branchName
		fi
		((index++))
	done
}

SearchServerByBranchName() {
	shift
	if [[ $# == 0 ]]; then
		return
	fi
	echo
	searchBranchName=$1
	for servicePath in "$GOPATH"/src/jspp/*; do
		if [[ -f $servicePath ]]; then
			continue
		fi
		cd $servicePath || continue
		if ! git status >/dev/null 2>&1; then
			continue
		fi
		local exists=0
		for branchName in $(git --no-pager branch | gawk '{gsub(/(*|\s)/,"",$0);print $0;}'); do
			if [[ $branchName == $searchBranchName ]]; then
				exists=1
				break
			fi
		done
		if [[ $exists == "1" ]]; then
			printf "%s\n" $(basename $servicePath)
			((index++))
		fi
	done
}

Setup() {
	for sourceFilename in "$SHELL_FOLDER"/../resources/*; do
		sourceFilename=$(realpath $sourceFilename)
		filename=$HOME/.$(basename $(realpath $sourceFilename))
		if [[ -f $filename ]]; then
			if [[ $sourceFilename != $(readlink -f $filename) ]]; then
				echo $filename
			fi
		else
			echo ln -sf $sourceFilename $filename';'
		fi
	done
}

Add() {
	shift
	if [[ ! -f $1 ]] && [[ ! -d $1 ]]; then
		echo param error!
		return
	fi
	mv $1 "$SHELL_FOLDER"/../resources/
	Setup
}

RemoveDuplicatePath() {
	gawk 'BEGIN{FixedPath()}'
}

UrlEncode() {
	shift
	if [[ $# == 0 ]]; then
		return
	fi
	gawk 'BEGIN{print UrlEncode("'$1'")}'
}

UrlDecode() {
	shift
	if [[ $# == 0 ]]; then
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
				break
			fi
		done
	done
}

ArrayIntersectNot() {
	echo
	arr=(${2//,/ })
	arr2=(${3//,/ })
	for out in ${arr[@]}; do
		out=$(echo $out | gawk '{print Trim($0)}')
		local isFind=0
		for iin in ${arr2[@]}; do
			if [[ $out == $iin ]]; then
				isFind=1
				break
			fi
		done
		if [[ $isFind == "0" ]]; then
			echo $out
		fi
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
	cd ~ || exit 131
	cd $GO_JSPP_WORKSPACE || exit 131
	cd testgo || exit 131
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
	logOption='--tail 20'
	if [ "$option" != "" ]; then
		logOption=$(echo "$option" | tr -d "\\")
	fi
	for server in "${!ServiceServers[@]}"; do
		if [ "$server" != "$service" ]; then
			continue
		fi
		awkString=" awk -F'[ -]()' "" '{print \"jspp-kubectl logs -c $service $logOption \"\$1\"-\"\$2\"-\"\$3}'"
		for i in $(jspp-kubectl get pods | grep "$service"); do
			result=$(echo "$i" | sed 's/(//' | sed 's/)//' | sed 's/\n\r//g')
			break
		done
		if [ "$result" = "" ]; then
			echo no launch for $service
			break
		fi
		result2=$(eval "echo $result|$awkString")
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

PortForward() {
	local arr=("$@")
	unset arr[0]

	local template="%2s %-19s %-30s %-10s\n"
	printf "${template}" "ID" "SERVICE NAME" "POD NAME" "STATUS"
	local index=1
	if [[ ${#arr[@]} -gt 0 ]]; then
		for server in ${arr[@]}; do
			PortForwardSimple "${server}" "${ServiceServers[$server]}" ${index}
			((index++))
		done
	else
		for server in "${ServiceServersOrder[@]}"; do
			PortForwardSimple "${server}" "${ServiceServers[$server]}" ${index}
			((index++))
		done
	fi
	GeneralConfForNginx
}

PortForwardSimple() {
	local pid=$(ps -ef | grep "jspp port-forward $1" | awk '{print $2}')
	if [[ "$pid" != "" ]]; then
		kill -9 $pid
	fi
	if [[ "mongo mysql redis" == *"${1}"* ]]; then
		name="${1}-0"
		PortForwardSimpleDo2 "${name}" "${2}" >"/tmp/$1.log" 2>&1 &
	else
		name=$(jspp-kubectl get pods | grep "$1" | awk '{if(NR==1){print $1}}')
		if [[ "$name" == "" ]]; then
			return 1
		else
			PortForwardSimpleDo "${name}" "${2}" >"/tmp/$1.log" 2>&1 &
		fi
	fi
	local template="%02s %-19s %-30s %-10s\n"
	if [ ! $? ]; then
		printf "${template}" ${index} "${1}" "${name}" "failed"
	else
		printf "${template}" ${index} "${1}" "${name}" "success"
	fi
}

PortForwardSimpleDo() {
	name=$1
	port=$2
	local index=1
	local maxIndex=1000
	while true; do
		name=$(echo $name | awk -F'-' '{print $1}')
		name=$(jspp-kubectl get pods | grep "$name" | awk '{if(NR==1){print $1}}')
		if [[ "$name" == "" ]]; then
			return 1
		fi
		jspp-kubectl port-forward "${name}" "${port}:9090" >>/tmp/${name}.log 2>&1
		echo "${name} Port-forward connection lost. Retrying in 5 seconds..."
		sleep 5
		((index++))
		if [[ $index -gt $maxIndex ]]; then
			break
		fi
	done
}

PortForwardSimpleDo2() {
	name=$1
	port=$2
	local index=1
	local maxIndex=1000
	while true; do
		name=$(echo $name | awk -F'-' '{print $1}')
		name=$(jspp-kubectl get pods | grep "$name" | awk '{if(NR==1){print $1}}')
		if [[ "$name" == "" ]]; then
			return 1
		fi
		jspp-kubectl port-forward "${name}" --address 0.0.0.0 "${port}:${port}" >>/tmp/${name}.log 2>&1
		echo "${name} Port-forward connection lost. Retrying in 5 seconds..."
		sleep 5
		((index++))
		if [[ $index -gt $maxIndex ]]; then
			break
		fi
	done
}

UnPortForward() {
	ps -ef | grep kubectl | awk '{print $2}' | xargs kill -9
	ps -ef | grep 'start.sh PortForward' | awk '{print $2}' | xargs kill -9
}

UpdateGitHook() {
	cd $GOPATH/src/jspp || exit 131
	for forService in "$GOPATH"/src/jspp/**; do
		if [ ! -d $forService ] || [ ! -d "$forService/.git/hooks" ] || [ ! -f "$forService/Makefile" ]; then
			printf "%-12s %s\n" $forService "failed"
			continue
		fi
		if cp -rf $SHELL_FOLDER/../resources/{commit-msg,pre-commit} "$forService/.git/hooks" >/dev/null; then
			printf "%-12s %s\n" $forService "success"
		else
			printf "%-12s %s\n" $forService "failed"
		fi
	done
}

Ip() {
	ifconfig | grep "inet 192" | grep -v '127.0.0.1' | awk -F "inet" '{print $2}' | awk -F "netmask" '{print $1}' | sed 's/^[[:space:]]*//g'
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
	declare -A DebugServers=(
		#["adminsv"]=19091
		#["edgesv"]=19092
		#["openapi"]=19093
		#["messagesv"]=19094
		#["paysv"]=19095
		#["pushersv"]=19097
		#["authsv"]=19098
		#["uploadsv"]=19099
		["usersv"]=19100
		#["squaresv"]=19101
		#["groupsv"]=19102
		#["net-security-data-report"]=19103
		#["chatbot"]=19104
		#["deliversv"]=19105
		#["riskcontrolsv"]=19106
		["momentsv"]=19107
	)
	filename=/usr/local/etc/nginx/servers/rpc.conf
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
            listen 9090;
       		grpc_connect_timeout 1h;
        	grpc_read_timeout 1h;
        	grpc_send_timeout 1h;
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
	if ps -ef | grep nginx >/dev/null; then
		/usr/local/bin/nginx -s reload
	else
		brew services reload nginx
	fi
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
	cd $HOME/Workdata/goland/src/jspp || exit 131
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
	cd $path || exit 131
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
		cd $item || exit 131
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

Rand() {
	if [[ "$1" == "" ]]; then
		return
	fi
	min=$1
	max=$((2 - min + 1))
	num=$((RANDOM + 1000000000))
	echo $((num % max + min))
}

UniquePATH() {
	if [[ $(IsLinux) ]]; then
		return
	fi
	export PATH=$(gawk 'BEGIN{UniquePATH()}')
}

StartClash() {
	/usr/local/bin/clash >/tmp/clash.log 2>&1 &
	port=$(netstat -natp 2>/dev/null | grep -i listen | grep "9090" | awk 'BEGIN{FS="[ /]+"}{print $7}')
	if [[ $port != "" && $port -gt 0 ]]; then
		echo $port >/var/run/clash-service.pid
	fi
}

IsLinux() {
	if [[ $(uname) == 'Linux' ]]; then
		return 0
	fi
	return 1
}

KeepaliveForword() {
	count=$(netstat -nat -p tcp | grep -i listen | grep -c 3306)
	if "$count" != ""; then
		return
	fi
	PortForward "$@"
}

StartAdminWebsite() {
	if [[ $(node --version) != "v14.21.3" ]]; then
		nvm use v14 --default
	fi
	cd $GOPATH/src/jspp/admin-website || exit 1
	npm run dev >/tmp/StartAdminWebsite.log 2>&1 &
}
