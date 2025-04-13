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

```shell
docker run --rm -p 63791:6379 --name rdb -v ./rdb:/data redis redis-server redis.conf
```

###### aof增量备份

```shell
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

```shell
docker run --rm -p 63791:6379 --name aof -v ./aof:/data redis redis-server redis.conf


```

###### 主节点关键配置

```
bind 0.0.0.0 #允许所有ip(或指定从节点ip)
protected-mode no # 关闭保护模式
requirepass "111111" #设置密码
save 900 1 # 启用持久化
save 300 10 
save 60 10000

```

###### 启动主从节点

```shell
# 分别启动主从节点
docker run --rm -p 16379:6379 --name master -v ./sentinel:/data redis redis-server master.conf
docker run --rm -p 26379:6379 --name slave -v ./sentinel:/data redis redis-server slave.conf
```

###### 启动sentinel进程并连接master进程

```shell
# 分别启动sentinel进程
docker run --rm -p 36379:26379 --name master-sentinel-001 -v ./sentinel:/data/ redis redis-sentinel sentinel-001.conf
docker run --rm -p 46379:26379 --name master-sentinel-002 -v ./sentinel:/data/ redis redis-sentinel sentinel-002.conf
docker run --rm -p 56379:26379 --name master-sentinel-003 -v ./sentinel:/data/ redis redis-sentinel sentinel-003.conf
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
docker network create \
  --driver=bridge \
  --subnet=192.168.100.0/24 \
  --gateway=192.168.100.1 \
  my-static-network
```

创建集群

```shell
redis-cli --cluster create \
  192.168.100.101:6379 \
  192.168.100.102:6379 \
  192.168.100.103:6379 \
  192.168.100.104:6379 \
  192.168.100.105:6379 \
  192.168.100.106:6379 \
  --cluster-replicas 1 \  
  -a 111111  

```
