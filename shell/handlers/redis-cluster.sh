#!/bin/bash
shopt -s nullglob
shopt -s dotglob

isRunning() {
    if docker ps >/dev/null 2>&1; then
        return
    fi
    echo "Is the docker daemon running?"
    return 1
}

isUsed() {
    local port=$1
    if [[ ! $port ]]; then
        return
    fi
    if lsof -i :$port | sed '1d' | grep -i listen >/dev/null 2>&1; then
        echo "Ports occupied($port)"
        return
    fi
    return 1
}

InitRedisCliRc() {
    local dir=$1
    read -r -d '' template <<EOF
:set hints
EOF
    workDir="${SHELL_FOLDER}"/../docker/redis
    filename=${workDir}/$dir/.redisclirc
    sureDir $filename
    if [ -f filename ]; then
        return
    fi
    echo "$template" >$filename
}

StartRedisCluster() {
    local index=1
    local port=16371
    local dockerNum=8
    readonly requirepass=111111
    readonly dockerNum
    InitRedisCliRc cluster
    local createCluster="docker exec -it cluster$port redis-cli -p $port -a 111111 --cluster-replicas 1 --no-auth-warning --cluster create --cluster-yes "
    ip=$(ifconfig en0 | grep "inet\b" | awk '{print $2}')
    if isUsed $port; then
        return
    fi
    if ! isRunning; then
        return
    fi
    ClearRedisClusterConf
    while ((index <= dockerNum)); do
        if isUsed $port; then
            return
        fi
        filename="${SHELL_FOLDER}"/../docker/redis/cluster/redis-cluster-$port.conf
        if [[ -f $filename ]]; then
            rm -rf $filename
        fi
        cat >$filename <<EOF
bind 0.0.0.0
cluster-enabled yes
syslog-enabled yes
cluster-node-timeout 5000
appendonly yes
requirepass $requirepass
masterauth $requirepass
port $port
cluster-config-file nodes-$port.conf
dbfilename dump-$port.rdb
appendfilename appendonly$port.aof
EOF
        dir=$(pwd)
        cd ${SHELL_FOLDER}/../docker/redis || exit 1
        read -r -d '' cmd<<EOF
            docker run -d --rm --name cluster$port --platform linux/amd64 -v ./cluster:/data --network host --cpus=2
                --memory=500m redis:6.2.17 redis-server $(basename $filename)  --loglevel verbose
EOF
        echo $cmd
        $cmd
        cd $dir || exit 2
        createCluster="${createCluster} $ip:$port"
        ((index++))
        ((port++))
    done
    sleep 1
    echo $createCluster
    $createCluster
}

ForceRestartRedisCluster() {
    StopRedisCluster
    StartRedisCluster
}

StopRedisCluster() {
    docker ps -f name=cluster | awk '{
        if(NR>1) {
            print $NF
        }
    }' | xargs -r docker stop
    ClearRedisClusterConf
}

ClearRedisClusterConf() {
    local index=1
    local port=16371
    local dockerNum=8
    while ((index <= dockerNum)); do
        if lsof -i :$port | sed '1d' | grep -i listen; then
            echo "first free up ports($port)"
            return
        fi
        names=(redis-cluster-$port.conf appendonly$port.aof dump-$port.rdb nodes-$port.conf .redisclirc)
        for name in ${names[@]}; do
            filename="${SHELL_FOLDER}"/../docker/redis/cluster/$name
            if [[ -f $filename ]]; then
                rm -rf $filename
            fi
        done
        ((index++))
        ((port++))
    done
}
