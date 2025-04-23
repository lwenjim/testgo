StopRedisSentinel() {
    docker ps -f name=sentinel | awk '{
        if(NR>1) {
            print $NF
        }
    }' | xargs -r docker stop
    ClearRedisSentinelConf
}

ClearRedisSentinelConf() {
    local index=1
    local port=15371
    local dockerNum=3
    while ((index <= dockerNum)); do
        if lsof -i :$port | sed '1d' | grep -i listen; then
            echo "first free up ports($port)"
            return
        fi
        names=(redis-sentinel-$port.conf appendonly$port.aof dump-$port.rdb nodes-$port.conf .redisclirc)
        for name in ${names[@]}; do
            filename="${SHELL_FOLDER}"/../docker/redis/sentinel/$name
            if [[ -f $filename ]]; then
                rm -rf $filename
            fi
        done
        ((index++))
        ((port++))
    done
}

StartRedisSentinel() {
    masterPort=14371
    local index=1
    local port=15371
    local dockerNum=3
    readonly requirepass=111111
    ip=$(ifconfig en0 | grep "inet\b" | awk '{print $2}')
    if isUsed $port; then
        return
    fi
    ClearRedisSentinelConf
    InitRedisCliRc sentinel
    while ((index <= dockerNum)); do
        if isUsed $port; then
            return
        fi
        filename="${SHELL_FOLDER}"/../docker/redis/sentinel/redis-sentinel-$port.conf
        if [[ -f $filename ]]; then
            rm -rf $filename
        fi
        cat >>$filename <<EOF
protected-mode no
port $port
daemonize no
pidfile "/var/run/redis-sentinel.pid"
loglevel verbose
logfile ""
dir "/tmp"
requirepass $requirepass
sentinel auth-pass mymaster $requirepass
sentinel auth-user mymaster default
sentinel sentinel-user default
sentinel sentinel-pass $requirepass

# 减少检测频率（默认 30 秒）
sentinel down-after-milliseconds mymaster 5000

# 增加故障转移超时时间（默认 3 分钟）
sentinel failover-timeout mymaster 180000

acllog-max-len 128
sentinel deny-scripts-reconfig yes
sentinel resolve-hostnames no
sentinel announce-hostnames no
EOF
        dir=$(pwd)
        cd ${SHELL_FOLDER}/../docker/redis || exit 1
        read -r -d '' cmd <<EOF
        docker run -d --rm --name sentinel-$port --platform linux/amd64 -v ./sentinel:/data/ --network host \
            --cpus=2 --memory=500m redis redis-sentinel $(basename $filename) --sentinel monitor mymaster $ip $masterPort 2 --loglevel verbose
EOF
        $cmd
        echo $cmd
        cd $dir || exit 2
        ((index++))
        ((port++))
    done
}
