###### 主库配置
```ini
[mysqld]
server-id = 1
log_bin = mysql-bin
binlog_format = ROW
max_binlog_size = 100M
binlog_do_db = test
```
###### 从库配置
```ini
[mysqld]
server-id = 2
log_bin = /var/lib/mysql/mysql-relay-bin.log
read_only = 1
relay_log = mysql-relay-bin
```

```shell
#### 创建子网

docker network create --subnet=192.168.100.0/24 my-static-network

CREATE USER 'replica_test'@'%' IDENTIFIED BY '11111111';
GRANT REPLICATION SLAVE ON *.* TO 'replica_test'@'%';
FLUSH PRIVILEGES;

FLUSH TABLES WITH READ LOCK;
SHOW MASTER STATUS;
UNLOCK TABLES;

docker run --rm --name master --network my-static-network --ip 192.168.100.101 \
-e MYSQL_ROOT_PASSWORD=123456 -v ./master-slave/master/localdata:/var/lib/mysql \
-v ./master-slave/master/conf.d:/etc/mysql/conf.d mysql:5.7.44

#### 从库配置
docker run --rm --name slave --network my-static-network --ip 192.168.100.102 -e MYSQL_ROOT_PASSWORD=123456 \
-v ./master-slave/slave/localdata:/var/lib/mysql -v ./master-slave/slave/conf.d:/etc/mysql/conf.d mysql:5.7.44

#### 配置主从同步
CHANGE MASTER TO MASTER_HOST = '192.168.100.101',MASTER_USER = 'replica_test',MASTER_PASSWORD = '11111111',MASTER_LOG_FILE = 'mysql-bin.000003',MASTER_LOG_POS = 755;
START SLAVE;

#### 开启从库只读权限
read_only = 1
super_read_only = 1

#### 检查非 InnoDB 表
SHOW TABLE STATUS WHERE Engine != 'InnoDB';

#### 用户拥有 SUPER 权限
SHOW GRANTS FOR 'root'@'%';

#### 禁止所有用户（包括SUPER用户）写操作
SET GLOBAL super_read_only = 1;

#### 回收用户的 SUPER 权限
REVOKE SUPER ON *.* FROM '用户'@'主机名';

#### 检查主从同步状态
SHOW SLAVE STATUS\G

Slave_IO_Running / Slave_SQL_Running：必须为 Yes
Last_IO_Error / Last_SQL_Error：查看具体错误信息
Seconds_Behind_Master：主从延迟时间（单位：秒）

# 2. 从库停止复制并重置
STOP SLAVE;
RESET SLAVE ALL;
mysql -uroot -p < full_backup.sql
CHANGE MASTER TO
  MASTER_HOST='主库IP',
  MASTER_USER='repl_user',
  MASTER_PASSWORD='密码',
  MASTER_LOG_FILE='mysql-bin.000001',  -- 从备份文件中查找
  MASTER_LOG_POS=154;                 -- 从备份文件中查找
START SLAVE;

#### 使用 pt-table-sync 修复

#### 预防数据不一致的最佳实践
**** 强制只读从库
read_only = 1
super_read_only = 1
**** 启用 GTID 复制
gtid_mode = ON
enforce_gtid_consistency = ON
-- 配置 GTID 复制
CHANGE MASTER TO MASTER_AUTO_POSITION = 1;

#### 定期数据校验

# 每周自动校验（添加到 crontab）
0 3 * * 6 pt-table-checksum --replicate=test.checksums h=主库IP,u=root,p=密码

#### 监控与告警
**** 监控 Seconds_Behind_Master 和复制线程状态
**** 使用 Prometheus + Grafana 可视化延迟和错误计数

#### 跳过单个错误事件
SET GLOBAL SQL_SLAVE_SKIP_COUNTER=1;

#### 查看 binlog 内容
SHOW BINLOG EVENTS IN 'mysql-bin.000001' FROM 154;

#### 停止/启动复制线程
STOP SLAVE; / START SLAVE;

#### 检查复制状态
SHOW SLAVE STATUS\G

```

