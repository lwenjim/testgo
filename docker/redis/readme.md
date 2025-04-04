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
docker run --rm -p 16379:6379 --name master -v ./master:/data redis redis-server redis.conf
docker run --rm -p 26379:6379 --name slave -v ./slave:/data/ redis redis-server redis.conf
```

###### 启动sentinel进程并连接master进程

```shell
# 分别启动sentinel进程
docker run --rm -p 36379:26379 --name master-sentinel-001 -v ./master:/data/ redis redis-sentinel sentinel-001.conf
docker run --rm -p 46379:26379 --name master-sentinel-002 -v ./master:/data/ redis redis-sentinel sentinel-002.conf
docker run --rm -p 56379:26379 --name master-sentinel-003 -v ./master:/data/ redis redis-sentinel sentinel-003.conf
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
