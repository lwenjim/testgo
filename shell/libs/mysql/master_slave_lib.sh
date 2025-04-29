StartMysqlMasterSlave() {
    local workDir="${SHELL_FOLDER}"/../docker/mysql
    local filename=${workDir}/masterslave/master/conf.d/config-file.cnf
    local masterPort=33066
    local slavePort=33067
    SureDir $filename
    if [[ ! -f $filename ]]; then
        cat >$filename <<EOF
[mysqld]
port=$masterPort
server-id = 1
log_bin = mysql-bin
binlog_format = ROW
max_binlog_size = 100M
binlog_do_db = test
EOF
    fi

    local filename=${workDir}/masterslave/slave/conf.d/config-file.cnf
    SureDir $filename
    if [[ ! -f $filename ]]; then
        cat >$filename <<EOF
[mysqld]
port=$slavePort
server-id = 2
log_bin = /var/lib/mysql/mysql-relay-bin.log
read_only = 1
relay_log = mysql-relay-bin
EOF
    fi

    read -r -d '' cmd <<EOF
docker run -d --rm --name mysql-master --platform linux/amd64 --network host \
-e MYSQL_ROOT_PASSWORD=123456 -v ./masterslave/master/localdata:/var/lib/mysql \
-v ./masterslave/master/conf.d:/etc/mysql/conf.d mysql:5.7.44
EOF
    $cmd
    echo $cmd

    #     local filename=${workDir}/masterslave/master/localdata/sql.sql
    #     if [[ ! -f $filename ]]; then
    #         cat >$filename <<EOF
    #     CREATE USER 'replica_test'@'%' IDENTIFIED BY '11111111';
    #     GRANT REPLICATION SLAVE ON *.* TO 'replica_test'@'%';
    #     FLUSH PRIVILEGES;

    #     FLUSH TABLES WITH READ LOCK;
    #     SHOW MASTER STATUS;
    #     UNLOCK TABLES;
    # EOF
    #     fi
    #     docker exec -it master mysql -h127.0.0.1 -uroot -p123456 -e "source /var/lib/mysql/sql.sql;source /var/lib/mysql/sql.sql;"

    read -r -d '' cmd <<EOF
docker run -d --rm --name mysql-slave --platform linux/amd64 --network host \
-e MYSQL_ROOT_PASSWORD=123456 -v ./masterslave/slave/localdata:/var/lib/mysql \
-v ./masterslave/slave/conf.d:/etc/mysql/conf.d mysql:5.7.44
EOF
    $cmd
    echo $cmd

    ip=$(ifconfig en0 | grep "inet\b" | awk '{print $2}')
    eval $(docker exec -it mysql-master mysql -h$ip -P$masterPort -uroot -p123456 -e "SHOW MASTER STATUS;" | gawk -F'|' '{if(NR==5){print "file="Trim($2)" pos="Trim($3)}}')
    read -r -d '' sql <<EOF
CHANGE MASTER TO MASTER_HOST = '$ip:$masterPort',MASTER_USER = 'root',MASTER_PASSWORD = '',MASTER_LOG_FILE = '$file',MASTER_LOG_POS = $pos;
START SLAVE;
EOF
    echo $sql

    read -r -d '' cmd <<EOF
    docker exec -it mysql-master mysql -h$ip -P$slavePort -uroot -p123456 -e "$sql"
EOF
    $cmd
    echo $cmd
}
