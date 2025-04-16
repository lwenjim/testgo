package redis

import (
	"context"
	"fmt"
	"math/rand"
	"time"

	"github.com/go-redis/redis/v8"
	"github.com/spf13/cobra"
)

var RedisCmd = &cobra.Command{
	Use: "redis",
	Run: func(cmd *cobra.Command, args []string) {
		Sentinel()
	},
}

func Diagnosis() {
	ctx := context.Background()
	sentinelClient := redis.NewSentinelClient(&redis.Options{
		Addr:     "localhost:36379",
		Password: "",
	})

	for {
		masterAddr, err := sentinelClient.GetMasterAddrByName(ctx, "mymaster").Result()
		if err != nil {
			panic(fmt.Sprintf("获取主节点失败: %v", err))
		}
		fmt.Printf("time: %v, masterAddr: %v\n", time.Now().Format("2006-01-02 15:04:05"), masterAddr)
		time.Sleep(1 * time.Second)
	}
}

func Sentinel() {
	ctx := context.Background()
	sentinelClient := redis.NewSentinelClient(&redis.Options{
		Addr:     "localhost:36379",
		Password: "",
	})

	masterAddr, err := sentinelClient.GetMasterAddrByName(ctx, "mymaster").Result()
	if err != nil {
		panic(fmt.Sprintf("获取主节点失败: %v", err))
	}

	cmd := sentinelClient.Slaves(ctx, "mymaster")
	res2, _ := cmd.Result()
	slaveConfig := map[string]string{}
	items := res2[0].([]interface{})
	for i := 0; i < len(items)-1; i++ {
		slaveConfig[items[i].(string)] = items[i+1].(string)
		i++
	}

	masterClient := redis.NewClient(&redis.Options{
		Addr:     fmt.Sprintf("%s:%s", masterAddr[0], masterAddr[1]),
		Password: "111111",
	})

	slaveClient := redis.NewClient(&redis.Options{
		Addr:     fmt.Sprintf("%s:%s", slaveConfig["name"], slaveConfig["port"]),
		Password: "111111",
	})

	err = masterClient.Set(ctx, "key2", "value2", 0).Err()
	if err != nil {
		panic(err)
	}

	val, err := slaveClient.Get(ctx, "key2").Result()
	if err != nil {
		panic(err)
	}
	fmt.Println("key2 的值为:", val)
}

func Check() {
	var (
		ctx          = context.Background()
		slaveAddrs   = []string{"172.17.0.3:6379"}
		slaveClients []*redis.Client
	)
	var (
		masterClient *redis.Client
		slaveClient  *redis.Client
	)

	masterClient = redis.NewClient(&redis.Options{
		Addr:     "172.17.0.2:6379",
		Password: "111111",
		DB:       0,
	})

	slaveClient = redis.NewClient(&redis.Options{
		Addr:     "172.17.0.3:6379",
		Password: "",
		DB:       0,
	})

	if _, err := masterClient.Ping(ctx).Result(); err != nil {
		panic(fmt.Sprintf("主节点连接失败: %v", err))
	}

	if _, err := slaveClient.Ping(ctx).Result(); err != nil {
		panic(fmt.Sprintf("从节点连接失败: %v", err))
	}

	err := masterClient.Set(ctx, "key1", "value1", 0).Err()
	if err != nil {
		panic(err)
	}

	val, err := slaveClient.Get(ctx, "key1").Result()
	if err != nil {
		panic(err)
	}
	fmt.Println("key1 的值为:", val)

	for _, addr := range slaveAddrs {
		client := redis.NewClient(&redis.Options{
			Addr:     addr,
			Password: "",
			DB:       0,
		})
		if _, err := client.Ping(ctx).Result(); err != nil {
			panic(fmt.Sprintf("从节点 %s 连接失败: %v", addr, err))
		}
		slaveClients = append(slaveClients, client)
	}

	r := rand.New(rand.NewSource(time.Now().UnixMicro()))
	client := slaveClients[r.Intn(len(slaveClients))]
	val, err = client.Get(ctx, "key1").Result()
	if err != nil {
		panic(err)
	}
	fmt.Println("key1 的值为:", val)

	masterClient = redis.NewClient(&redis.Options{
		Addr:         "172.17.0.2:6379",
		Password:     "",
		DB:           0,
		PoolSize:     20,
		MinIdleConns: 5,
	})

	maxRetries := 3
	for i := 0; i < maxRetries; i++ {
		err := masterClient.Set(ctx, "key", "value", 0).Err()
		if err == nil {
			break
		}
		time.Sleep(1 * time.Second)
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

func ClusterRedis() {
	ctx := context.Background()
	Cluster := redis.NewClusterClient(&redis.ClusterOptions{
		Addrs: []string{
			"192.168.100.101:6379",
			"192.168.100.102:6379",
			"192.168.100.103:6379",
		},
		Password:     "111111",
		DialTimeout:  10 * time.Second,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
	})

	// Cluster.Set(context.TODO(), SampleDemoKey, "666", 10*time.Minute)
	// cmd := Cluster.Get(context.TODO(), SampleDemoKey)
	// result, err := cmd.Result()
	// fmt.Println("err:", err)
	// fmt.Println("result:", result)

	err := Cluster.ForEachMaster(ctx, func(ctx context.Context, shard *redis.Client) error {
		return shard.Ping(ctx).Err()
	})
	if err != nil {
		panic(err)
	}
}

func MasterSlave() {
	ctx := context.Background()
	masterClient := redis.NewClient(&redis.Options{
		Addr:     "localhost:16379",
		Password: "111111",
		DB:       0,
	})

	replicaClient := redis.NewClient(&redis.Options{
		Addr:     "localhost:26379",
		Password: "",
		DB:       0,
	})

	err := masterClient.Set(ctx, "key", "value", 0).Err()
	if err != nil {
		panic(err)
	}

	val, err := replicaClient.Get(ctx, "key").Result()
	if err != nil {
		panic(err)
	}
	fmt.Println("key", val)
}
