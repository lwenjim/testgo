###### rdb备份
```shell
# 备份文件名
dbfilename dump.rdb
# 存放备份文件的文件夹
dir ./
# 数据压缩
rdbcompression yes
# 触发rdb快照
save
flushall
shutdown
# 恢复数据  拷贝 dump.rdb 到 bin目录下面 运行服务即可

```

###### aof 增量备份
```conf
bind 0.0.0.0 #允许所有ip(或指定从节点ip)
protected-mode no # 关闭保护模式
requirepass "111111" #设置密码
save 900 1 # 启用持久化
save 300 10
save 60 10000

# 开启增量备份
appendonly yes
# 指定增量备份文件名称
appendfilenname appenonly.aof
# appendasync always/everysec/no
appendfsync everysec
# 配置重写触发机制
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64m

```

###### 主从模式
```shell
docker run --rm --name master -v ./masterslave:/data --network my-static-network --ip 192.168.100.101 --cpus=2 --memory=500m redis redis-server master.conf --loglevel verbose
docker run --rm --name slave  -v ./masterslave:/data --network my-static-network --ip 192.168.100.102 --cpus=2 --memory=500m redis redis-server slave.conf  --loglevel verbose --replicaof 192.168.100.101 6379
```

###### sentinel模式
```shell
# 分别启动主从节点
docker run --rm -p 16379:6379 --name sentinel-master -v ./sentinel:/data --network my-static-network --ip 192.168.100.201 --cpus=2 --memory=500m redis redis-server master.conf --loglevel verbose
docker run --rm -p 26379:6379 --name sentinel-slave  -v ./sentinel:/data --network my-static-network --ip 192.168.100.202 --cpus=2 --memory=500m redis redis-server slave.conf  --loglevel verbose --replicaof 192.168.100.201 6379

# 分别启动sentinel进程
docker run --rm -p 36379:26379 --name master-sentinel-001 -v ./sentinel:/data/ --network my-static-network --ip 192.168.100.203 --cpus=2 --memory=500m redis redis-sentinel sentinel-001.conf --sentinel monitor mymaster 192.168.100.201 6379 2 --loglevel verbose
docker run --rm -p 46379:26379 --name master-sentinel-002 -v ./sentinel:/data/ --network my-static-network --ip 192.168.100.204 --cpus=2 --memory=500m redis redis-sentinel sentinel-002.conf --sentinel monitor mymaster 192.168.100.201 6379 2 --loglevel verbose
docker run --rm -p 56379:26379 --name master-sentinel-003 -v ./sentinel:/data/ --network my-static-network --ip 192.168.100.205 --cpus=2 --memory=500m redis redis-sentinel sentinel-003.conf --sentinel monitor mymaster 192.168.100.201 6379 2 --loglevel verbose

docker run --rm -p 36379:26379 --name master-sentinel-001 -v ./sentinel:/data/ --network my-static-network --ip 192.168.100.203 --cpus=2 --memory=500m redis redis-sentinel sentinel-001.conf --loglevel verbose
docker run --rm -p 46379:26379 --name master-sentinel-002 -v ./sentinel:/data/ --network my-static-network --ip 192.168.100.204 --cpus=2 --memory=500m redis redis-sentinel sentinel-002.conf --loglevel verbose
docker run --rm -p 56379:26379 --name master-sentinel-003 -v ./sentinel:/data/ --network my-static-network --ip 192.168.100.205 --cpus=2 --memory=500m redis redis-sentinel sentinel-003.conf --loglevel verbose
```

###### 集群(cluster)模式
```shell
docker run --rm --name cluster001 -v ./cluster:/data --network my-static-network --ip 192.168.100.11 --cpus=2 --memory=500m redis:6.2.17 redis-server redis-cluster-001.conf --loglevel verbose
docker run --rm --name cluster002 -v ./cluster:/data --network my-static-network --ip 192.168.100.12 --cpus=2 --memory=500m redis:6.2.17 redis-server redis-cluster-002.conf --loglevel verbose
docker run --rm --name cluster003 -v ./cluster:/data --network my-static-network --ip 192.168.100.13 --cpus=2 --memory=500m redis:6.2.17 redis-server redis-cluster-003.conf --loglevel verbose
docker run --rm --name cluster004 -v ./cluster:/data --network my-static-network --ip 192.168.100.14 --cpus=2 --memory=500m redis:6.2.17 redis-server redis-cluster-004.conf --loglevel verbose
docker run --rm --name cluster005 -v ./cluster:/data --network my-static-network --ip 192.168.100.15 --cpus=2 --memory=500m redis:6.2.17 redis-server redis-cluster-005.conf --loglevel verbose
docker run --rm --name cluster006 -v ./cluster:/data --network my-static-network --ip 192.168.100.16 --cpus=2 --memory=500m redis:6.2.17 redis-server redis-cluster-006.conf --loglevel verbose
docker run --rm --name cluster007 -v ./cluster:/data --network my-static-network --ip 192.168.100.17 --cpus=2 --memory=500m redis:6.2.17 redis-server redis-cluster-007.conf --loglevel verbose
docker run --rm --name cluster008 -v ./cluster:/data --network my-static-network --ip 192.168.100.18 --cpus=2 --memory=500m redis:6.2.17 redis-server redis-cluster-008.conf --loglevel verbose

docker run --rm --name cluster011 -v ./cluster:/data --network host --cpus=2 --memory=500m redis:6.2.17 redis-server redis-cluster-001.conf --loglevel verbose

创建集群
docker exec -it cluster001 redis-cli --cluster create \
192.168.100.11:6379  \
192.168.100.12:6379  \
192.168.100.13:6379  \
192.168.100.14:6379  \
192.168.100.15:6379  \
192.168.100.16:6379  \
192.168.100.17:6379  \
192.168.100.18:6379  \
--cluster-replicas 1  -a 111111

redis-cli -a cc --cluster reshard 192.168.163.132:6379 --cluster-from 117457eab5071954faab5e81c3170600d5192270 --cluster-to 815da8448f5d5a304df0353ca10d8f9b77016b28 --cluster-slots 10 --cluster-yes --cluster-timeout 5000 --cluster-pipeline 10 --cluster-replace
redis-cli -a cc --cluster rebalance --cluster-weight 117457eab5071954faab5e81c3170600d5192270=5 815da8448f5d5a304df0353ca10d8f9b77016b28=4 56005b9413cbf225783906307a2631109e753f8f=3 --cluster-simulate 192.168.163.132:6379
redis-cli --cluster add-node 192.168.163.132:6382 192.168.163.132:6379 --cluster-slave --cluster-master-id 117457eab5071954faab5e81c3170600d5192270
redis-cli --cluster del-node 192.168.163.132:6384 f6a6957421b80409106cb36be3c7ba41f3b603ff
redis-cli --cluster fix 192.168.163.132:6384 --cluster-search-multiple-owners
redis-cli --cluster call 192.168.163.132:6381 config set cluster-node-timeout 12000
```


节点配置
```shell
# 节点 1 配置（主节点）
port 6379
bind 0.0.0.0                     # 允许所有 IP 访问
cluster-enabled yes               # 启用集群模式
cluster-config-file nodes.conf    # 集群状态文件
cluster-node-timeout 5000         # 节点超时时间（毫秒）
appendonly yes                    # 启用持久化
daemonize yes                     # 后台运行
logfile "/var/log/redis/redis.log"
requirepass yourpassword          # 集群密码（可选）
masterauth yourpassword           # 主从认证密码（与 requirepass 一致）
```

创建自定义网络
```shell
docker network create --driver=bridge --subnet=192.168.100.0/24 --gateway=192.168.100.1 my-static-network
```

sentinel常用管理命令
```shell
# 查看故障转移状态
SENTINEL failover mymaster

# 查看主节点信息
SENTINEL master mymaster

# 查看所有Sentinel节点
SENTINEL sentinels mymaster

# 修改检测超时时间（根据网络状况调整，通常5-15秒）
SENTINEL set mymaster down-after-milliseconds 5000

# 调整故障转移超时
SENTINEL set mymaster failover-timeout 60000

docker stop master

# 查看QPS 指标 instantaneous_ops_per_sec
redis-cli info stats | grep instantaneous_ops_per_sec  # 查看当前 QPS

# 查看 master_repl_offset 和 slave_repl_offset 的差距。主从节点数据同步偏移量
redis-cli info replication

# 降低同步延迟
# 增加复制缓冲区大小（默认 1MB，可适当调大）
redis-cli config set repl-backlog-size 256mb
# 限制主节点写入速度, 使用 pipeline 优化写入
# 手动触发同步 如果从节点长时间落后，可以尝试：
# 在从节点执行，重新同步数据（会清空从节点数据）
redis-cli replicaof no one  # 先取消复制
redis-cli flushall         # 清空数据（谨慎操作！）
redis-cli replicaof <master-ip> <master-port>  # 重新同步
# 监控复制状态
# 查看主从复制状态
redis-cli info replication
# 重点关注：
role:master/slave
master_repl_offset:xxx  # 主节点 offset
slave_repl_offset:xxx   # 从节点 offset
slave_lag:xxx           # 延迟量（Redis 5.0+）slave_lag > 0 表示有延迟。

#（连接是否正常）
master_link_status:up

#（是否和 Master 的 master_repl_offset 接近）
slave_repl_offset

# 查看 Sentinel 的 PING 频率
redis-cli -p 26379 sentinel debug mymaster

# 检查 PING 延迟
redis-cli -p 15371 -a 111111 --no-auth-warning --json --latency


```

网络测试工具
```shell
# 从宿主机 ping 容器 IP
ping 172.17.0.2

# 检查端口是否可达
telnet 172.17.0.2 6379
nc -zv 172.17.0.2 6379

# 进入容器
docker exec -it redis bash

# 安装 net-tools
apt update && apt install net-tools -y

# 查看端口监听
netstat -tuln | grep 6379
```

查看桥接成员
```shell
# 查看 bridge0 的成员接口
ifconfig bridge0 | grep member
```

跟踪网络流量
```shell
# 在宿主机抓包（替换为容器 IP）
tcpdump -i docker0 host 172.17.0.2 and port 6379

# 另开终端执行访问测试
redis-cli -h 172.17.0.2 PING
```

```conf
# 禁用 flushall
rename-command FLUSHALL ""
protected-mode	yes	是否开启保护模式。若未设置密码且 bind 未指定 IP，禁止外部访问。
```