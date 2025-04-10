```shell
# see https://juejin.cn/post/7115157880008867871

/usr/local/opt/mongodb-community/bin/mongod --port 27011 --dbpath ./master/11 --bind_ip 0.0.0.0 --replSet  ymx/localhost:27012
/usr/local/opt/mongodb-community/bin/mongod --port 27012 --dbpath ./master/12 --bind_ip 0.0.0.0 --replSet  ymx/localhost:27013
/usr/local/opt/mongodb-community/bin/mongod --port 27013 --dbpath ./master/13 --bind_ip 0.0.0.0 --replSet  ymx/localhost:27011

# 进入MongoDB客户端界面
var config = { 
...     _id:"ymx", 
...     members:[
...         {_id:0,host:"localhost:27011"},
...         {_id:1,host:"localhost:27012"},
...         {_id:2,host:"localhost:27013"}]
...     }
> rs.initiate(config);

# Driver的URL
mongodb://127.0.0.1:27017,127.0.0.1:27018,127.0.0.1:27019/ems(库名)?replcaSet=spock(副本集名称)
```

```shell
#Shard节点
/usr/local/opt/mongodb-community/bin/mongod --port 27021 --dbpath ./master/21 --bind_ip 0.0.0.0 --shardsvr --replSet "shards"/localhost:27022

/usr/local/opt/mongodb-community/bin/mongod --port 27022 --dbpath ./master/22 --bind_ip 0.0.0.0 --shardsvr --replSet "shards"/localhost:27021

#Config Servers节点副本集
/usr/local/opt/mongodb-community/bin/mongod --port 27100 --dbpath ./master/conf/00 --bind_ip 0.0.0.0 --replSet "configs"/localhost:27101 --configsvr

/usr/local/opt/mongodb-community/bin/mongod --port 27101 --dbpath ./master/conf/01 --bind_ip 0.0.0.0 --replSet "configs"/localhost:27100 --configsvr

#Router节点
/usr/local/opt/mongodb-community/bin/mongos --port 27999 --configdb "configs"/localhost:27100,localhost:27101 --bind_ip 0.0.0.0




```
