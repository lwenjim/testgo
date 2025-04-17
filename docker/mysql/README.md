```shell
# https://xiaomi-info.github.io/2020/01/02/distributed-transaction/
```

#### 创建子网
```shell
docker network create --subnet=192.168.100.0/24 my-static-network
```

#### 主库配置
```sql
CREATE USER 'replica_test'@'%' IDENTIFIED BY '11111111';
GRANT REPLICATION SLAVE ON *.* TO 'replica_test'@'%';
FLUSH PRIVILEGES;
```
```shell
docker run --rm --name master --network my-static-network --ip 192.168.100.101 -e MYSQL_ROOT_PASSWORD=123456 -v ./master-slave/master/mysql:/var/lib/mysql -p 13306:3306 -v ./master-slave/master/conf.d:/etc/mysql/conf.d mysql
```

#### 从库配置
```shell
docker run --rm --name slave --network my-static-network --ip 192.168.100.102 -e MYSQL_ROOT_PASSWORD=123456 -v ./master-slave/slave/mysql:/var/lib/mysql -p 23306:3306 -v ./master-slave/slave/conf.d:/etc/mysql/conf.d mysql
```

#### 配置主从同步
```sql
CHANGE MASTER TO MASTER_HOST = '192.168.100.101',MASTER_USER = 'replica_test',MASTER_PASSWORD = '11111111',MASTER_LOG_FILE = 'mysql-bin.000001',  MASTER_LOG_POS = 0;
```

