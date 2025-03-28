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

```
# 分别启动主从节点
docker run --rm -p 16379:6379 --name master -v ./master:/data redis redis-server redis.conf
docker run --rm -p 26379:6379 --name slave -v ./slave:/data/ redis redis-server redis.conf
```

###### 启动sentinel进程并连接master进程

```
# 分别启动sentinel进程
docker run --rm -p 36379:26379 --name master-sentinel-001 -v ./master:/data/ redis redis-sentinel sentinel-001.conf
docker run --rm -p 46379:26379 --name master-sentinel-002 -v ./master:/data/ redis redis-sentinel sentinel-002.conf
docker run --rm -p 56379:26379 --name master-sentinel-003 -v ./master:/data/ redis redis-sentinel sentinel-003.conf
```
