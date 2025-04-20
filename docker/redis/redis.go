package redis

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/go-redis/redis/v8"
	"github.com/spf13/cobra"
)

var (
	password   string = "111111"
	masterName        = "mymaster"
	RedisCmd          = &cobra.Command{
		Use: "redis",
		Run: func(cmd *cobra.Command, args []string) {
			Sentinel()
		},
	}
)

func Sentinel() {
	ctx := context.Background()
	sentinel := redis.NewSentinelClient(&redis.Options{
		Addr:     "localhost:15371",
		Password: password,
	})

	masterAddr, err := sentinel.GetMasterAddrByName(ctx, masterName).Result()
	if err != nil {
		panic(fmt.Sprintf("获取主节点失败: %v", err))
	}

	master := redis.NewClient(&redis.Options{
		Addr:     fmt.Sprintf("%s:%s", masterAddr[0], masterAddr[1]),
		Password: password,
	})

	err = master.Set(ctx, "key2", "value2", 0).Err()
	if err != nil {
		fmt.Println(err)
		return
	}

	masterInterfaces, err := sentinel.Masters(ctx).Result()
	if err != nil {
		fmt.Println(err)
		return
	}
	masterCfgs, err := ParseResponse(masterInterfaces)
	if err != nil {
		fmt.Println(err)
		return
	}
	printTable("Master配置", masterCfgs)

	slaveCfgs, err := GetSlavesFromSentinel(sentinel, masterName)
	if err != nil {
		fmt.Println(err)
		return
	}
	printTable("Slave配置", slaveCfgs)
	for _, c := range slaveCfgs {
		slave := redis.NewClient(&redis.Options{
			Addr:     fmt.Sprintf("%s:%s", c["ip"], c["port"]),
			Password: password,
		})

		_, err := slave.Get(ctx, "key2").Result()
		if err != nil {
			fmt.Println(err)
			return
		}
	}
	_ = sentinel.Process(ctx, redis.NewStringCmd(ctx, "ping"))

	ck, err := sentinel.CkQuorum(ctx, masterName).Result()
	if err != nil {
		fmt.Println(err)
		return
	}
	fmt.Printf("ck: %v\n", ck)
	sentinelInfos, err := sentinel.Sentinels(ctx, masterName).Result()
	if err != nil {
		fmt.Println(err)
		return
	}
	sentinelCfgs, err := ParseResponse(sentinelInfos)
	if err != nil {
		fmt.Println(err)
		return
	}
	printTable("Sentinel配置", sentinelCfgs)
	res, err := sentinel.Ping(ctx).Result()
	if err != nil {
		fmt.Println(err)
		return
	}
	fmt.Printf("ping: %s\n", res)
}

func printTable(title string, sentinelCfgs []map[string]string) {
	maxKey := 0
	maxValue := 0
	for _, vs := range sentinelCfgs {
		for k, v := range vs {
			if len(k) > maxKey {
				maxKey = len(k)
			}
			if len(v) > maxKey {
				maxValue = len(v)
			}
		}
	}
	len := (maxValue + maxKey + 1 - len(title)) / 2
	fmt.Printf("\n\n\n\n%s %s %s\n", strings.Repeat("<", len), title, strings.Repeat(">", len))
	for _, vs := range sentinelCfgs {
		for k, v := range vs {
			fmt.Println(strings.Repeat("-", maxValue+maxKey+1))
			fmt.Printf("%-"+fmt.Sprintf("%d", maxKey)+"s:%s\n", k, v)
		}
	}
	fmt.Println(strings.Repeat("-", maxValue+maxKey+1))
}

func MasterSlave() {
	ctx := context.Background()
	master := redis.NewClient(&redis.Options{
		Addr:     "localhost:14371",
		Password: password,
		DB:       0,
	})

	if _, err := master.Ping(ctx).Result(); err != nil {
		panic(fmt.Sprintf("主节点连接失败: %v", err))
	}

	err := master.Set(ctx, "key1", "value1", 0).Err()
	if err != nil {
		fmt.Println(err)
		return
	}
	slavesCfg, err := GetReplicasUsingRole(master)
	if err != nil {
		fmt.Println(err)
		return
	}
	for _, addr := range slavesCfg {
		slave := redis.NewClient(&redis.Options{
			Addr:     addr,
			Password: password,
			DB:       0,
		})

		if _, err := slave.Ping(ctx).Result(); err != nil {
			panic(fmt.Sprintf("从节点连接失败: %v", err))
		}

		val, err := slave.Get(ctx, "key1").Result()
		if err != nil {
			panic(err)
		}
		fmt.Println("key1 的值为:", val)
	}
}

func ExecRedisScript() {
	ctx := context.Background()
	rdb := redis.NewUniversalClient(&redis.UniversalOptions{
		Addrs: []string{":6379"},
	})
	var incrBy = redis.NewScript(`
	local reply = redis.pcall('hgetall', 'abc')
	if reply["err"] ~= nil then
		redis.log(redis.LOG_WARNING, reply["err"])
		return ""
	end

	local mytable = {}
	for key, value in pairs(reply) do
		mytable[key] = value
	end

	return mytable
	`)
	keys := []string{"my_counter"}
	result, err := incrBy.Run(ctx, rdb, keys).StringSlice()
	if err != nil {
		fmt.Println(err)
		return
	}
	fmt.Printf("result: %v\n", result)
	arr := map[string]string{}
	for i := 0; i < len(result); i++ {
		arr[result[i]] = result[i+1]
		i++
	}
	fmt.Printf("arr: %v\n", arr)
}

func Diagnosis() {
	ctx := context.Background()
	sentinel := redis.NewSentinelClient(&redis.Options{
		Addr:     "localhost:36379",
		Password: "",
	})

	for {
		masterAddr, err := sentinel.GetMasterAddrByName(ctx, masterName).Result()
		if err != nil {
			panic(fmt.Sprintf("获取主节点失败: %v", err))
		}
		fmt.Printf("time: %v, masterAddr: %v\n", time.Now().Format("2006-01-02 15:04:05"), masterAddr)
		time.Sleep(1 * time.Second)
	}
}

func ClusterRedis() {
	ctx := context.Background()
	cluster := redis.NewClusterClient(&redis.ClusterOptions{
		Addrs: []string{
			"localhost:16372",
		},
		Password:     password,
		DialTimeout:  10 * time.Second,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
	})

	if err := cluster.ForEachMaster(ctx, func(ctx context.Context, shard *redis.Client) error {
		return shard.Ping(ctx).Err()
	}); err != nil {
		panic(err)
	}
	for {
		demoKey := fmt.Sprintf("%d", time.Now().UnixMicro())
		cluster.Set(ctx, demoKey, fmt.Sprintf("%d", time.Now().UnixMicro()), 10*time.Minute)
		if result, err := cluster.Get(ctx, demoKey).Result(); err != nil {
			fmt.Println("err:", err)
		} else {
			fmt.Println("result:", result)
		}
		time.Sleep(time.Second)
	}
}

func GetReplicasFromMaster(client *redis.Client) ([]string, error) {
	info, err := client.Info(context.Background(), "replication").Result()
	if err != nil {
		return nil, err
	}

	var replicas []string
	lines := strings.Split(info, "\r\n")
	for _, line := range lines {
		if strings.HasPrefix(line, "slave") && strings.Contains(line, "ip=") {
			parts := strings.Split(line, ",")
			var ip, port string
			for _, part := range parts {
				if strings.HasPrefix(part, "ip=") {
					ip = strings.TrimPrefix(part, "ip=")
				} else if strings.HasPrefix(part, "port=") {
					port = strings.TrimPrefix(part, "port=")
				}
			}
			if ip != "" && port != "" {
				replicas = append(replicas, fmt.Sprintf("%s:%s", ip, port))
			}
		}
	}

	return replicas, nil
}

func GetReplicasUsingRole(client *redis.Client) ([]string, error) {
	roleInfo, err := client.Do(context.Background(), "ROLE").Result()
	if err != nil {
		return nil, err
	}

	roleSlice, ok := roleInfo.([]interface{})
	if !ok || len(roleSlice) < 3 {
		return nil, fmt.Errorf("invalid ROLE response")
	}

	if roleSlice[0].(string) != "master" {
		return nil, fmt.Errorf("not a master node")
	}

	var replicas []string
	replicasInfo := roleSlice[2].([]interface{})
	for _, replica := range replicasInfo {
		replicaInfo := replica.([]interface{})
		if len(replicaInfo) >= 2 {
			ip := replicaInfo[0].(string)
			port := replicaInfo[1].(string)
			replicas = append(replicas, fmt.Sprintf("%s:%s", ip, port))
		}
	}

	return replicas, nil
}
func GetSlavesFromSentinel(client *redis.SentinelClient, masterName string) ([]map[string]string, error) {
	slavesInfo, err := client.Slaves(context.Background(), masterName).Result()
	if err != nil {
		return nil, fmt.Errorf("failed to get slaves from sentinel: %v", err)
	}
	return ParseResponse(slavesInfo)
}

func ParseResponse(slavesInfo []interface{}) ([]map[string]string, error) {
	var slaves []map[string]string
	for _, slave := range slavesInfo {
		slaveData, ok := slave.([]interface{})
		if !ok {
			continue
		}

		slaveMap := make(map[string]string)
		for i := 0; i < len(slaveData); i += 2 {
			if i+1 >= len(slaveData) {
				break
			}
			key, ok1 := slaveData[i].(string)
			value, ok2 := slaveData[i+1].(string)
			if ok1 && ok2 {
				slaveMap[key] = value
			}
		}
		slaves = append(slaves, slaveMap)
	}
	return slaves, nil
}
