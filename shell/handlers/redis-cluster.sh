#!/bin/bash
StartRedisCluster() {
    shopt -s nullglob
    shopt -s dotglob
    local index=1
    local port=16372
    local dockerNum=8
    local requirepass=111111
    local createCluster="docker exec -it cluster001 redis-cli --cluster create "
    readonly requirepass
    ip=$(ifconfig en0|grep "inet\b"|awk '{print $2}')
    docker ps >/dev/null 2>&1
    if (("$?" > "0")); then
        echo "Is the docker daemon running?"
        return
    fi
    ClearRedisClusterConf
    while ((index <= dockerNum)); do
        read -r -d '' template <<EOF
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
appendfilename appendonly00$port.aof
EOF
        filename="${SHELL_FOLDER}"/../docker/redis/cluster/redis-cluster-$port.conf
        if [[ -f $filename ]]; then
            rm -rf $filename
        fi
        echo "$template" >$filename
        dir=$(pwd)
        cd ${SHELL_FOLDER}/../docker/redis || exit 1
        docker run -d --rm --name cluster$port -v ./cluster:/data --network host --cpus=2 --memory=500m redis:6.2.17 redis-server $(basename $filename)  --loglevel verbose
        cd $dir
        createCluster="${createCluster} $ip:$port"
        ((index++))
        ((port++))
    done
    createCluster="${createCluster} --cluster-replicas 1 no-auth-warning  -a 111111"
    echo $createCluster
}

StopRedisCluster() {
    docker ps -f name=cluster | awk '{if(NR>1)print $10}' | xargs docker stop
    ClearRedisClusterConf
}

ClearRedisClusterConf() {
    local index=1
    local port=16372
    local dockerNum=8
    while ((index <= dockerNum)); do
        names=(redis-cluster-$port.conf appendonly$port.aof dump-$port.rdb nodes-$port.conf)
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
