#!/bin/bash
shopt -s nullglob
shopt -s dotglob

StopRedisMasterSlave() {
    docker ps -f name=masterslave | awk '{
        if(NR>1) {
            print $NF
        }
    }' | xargs -r docker stop
    ClearRedisMasterSlaveConf
}

sureDir() {
    local filename=$1
    dir=$(dirname $filename)
    if [[ -d $dir ]]; then
        return
    fi
    mkdir -p $dir
}

dd() {
    name=123
    read data <<EOF
name: $name
EOF
    echo $data
}

ClearRedisMasterSlaveConf() {
    local index=1
    local port=14371
    local dockerNum=3
    while ((index <= dockerNum + 1)); do
        if lsof -i :$port | sed '1d' | grep -i listen; then
            echo "first free up ports($port)"
            return
        fi
        names=(redis-master$port.conf redis-slave$port.conf slave$port.rdb master$port.rdb .redisclirc)
        for name in ${names[@]}; do
            filename="${SHELL_FOLDER}"/../docker/redis/masterslave/$name
            if [[ -f $filename ]]; then
                rm -rf $filename
            fi
        done
        ((index++))
        ((port++))
    done
}

StartRedisMasterSlave() {
    local index=1
    local port=14371
    readonly dockerNum=3
    readonly requirepass=111111
    readonly masterPort=$port
    InitRedisCliRc masterslave
    workDir="${SHELL_FOLDER}"/../docker/redis
    filename=${workDir}/masterslave/redis-master$masterPort.conf
    sureDir $filename
    cat >$filename <<EOF
bind 0.0.0.0
port $masterPort
protected-mode no
requirepass $requirepass
masterauth $requirepass
save 900 1
save 300 10
save 60 10000
dbfilename "master$masterPort.rdb"
EOF
    cd ${SHELL_FOLDER}/../docker/redis || exit 1
    read -r -d '' cmd <<EOF
    docker run -d --rm --name masterslave-master$port --platform linux/amd64 -v ./masterslave:/data --network host --cpus=2 \
    --memory=500m redis redis-server $(basename $filename) --loglevel verbose
EOF
    $cmd
    echo $cmd

    ip=$(ifconfig en0 | grep "inet\b" | awk '{print $2}')
    ((port++))
    while ((index <= dockerNum)); do
        if isUsed $port; then
            return
        fi
        filename=${workDir}/masterslave/redis-slave$port.conf
        if [[ -f $filename ]]; then
            rm -rf $filename
        fi
        cat >$filename <<EOF
port $port
requirepass $requirepass
masterauth $requirepass
bind 0.0.0.0
protected-mode no
dir "/data"
latency-tracking-info-percentiles 50 99 99.9
save 3600 1
save 300 100
save 60 10000
dbfilename "slave$port.rdb"
loglevel verbose
EOF
        dir=$(pwd)
        cd ${SHELL_FOLDER}/../docker/redis || exit 1
        read -r -d '' cmd <<EOF
        docker run -d --rm  --name masterslave-slave$port  --platform linux/amd64 -v ./masterslave:/data --network host --cpus=2 \
        --memory=500m redis redis-server $(basename $filename) --loglevel verbose --replicaof $ip $masterPort
EOF
        $cmd
        echo $cmd
        cd $dir || exit 2
        ((index++))
        ((port++))
    done
}
