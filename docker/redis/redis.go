package redis

import (
	"context"
	"fmt"
	"math/rand"
	"time"

	"github.com/go-redis/redis/v8"
	"github.com/spf13/cobra"
)

var (
	ctx          = context.Background()
	slaveAddrs   = []string{"172.17.0.3:6379"}
	slaveClients []*redis.Client
)
var (
	// 主节点客户端（写操作）
	masterClient *redis.Client
	// 从节点客户端（读操作）
	slaveClient *redis.Client
)
var Cluster *redis.ClusterClient

const SampleDemoKey = "SampleDemoKey"

func SampleDemo() {
	Cluster = redis.NewClusterClient(&redis.ClusterOptions{
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
	// 写入数据，并设置10分钟缓存
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

var RedisCmd = &cobra.Command{
	Use: "redis",
	Run: func(cmd *cobra.Command, args []string) {
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
	},
}

func Check() {
	// 初始化主节点连接
	masterClient = redis.NewClient(&redis.Options{
		Addr:     "172.17.0.2:6379",
		Password: "111111", // 密码（如果有）
		DB:       0,        // 数据库编号
	})

	// 初始化从节点连接
	slaveClient = redis.NewClient(&redis.Options{
		Addr:     "172.17.0.3:6379",
		Password: "",
		DB:       0,
	})

	// 检查主节点连接
	if _, err := masterClient.Ping(ctx).Result(); err != nil {
		panic(fmt.Sprintf("主节点连接失败: %v", err))
	}

	// 检查从节点连接
	if _, err := slaveClient.Ping(ctx).Result(); err != nil {
		panic(fmt.Sprintf("从节点连接失败: %v", err))
	}

	// 写入数据到主节点
	err := masterClient.Set(ctx, "key1", "value1", 0).Err()
	if err != nil {
		panic(err)
	}

	// 从从节点读取数据
	val, err := slaveClient.Get(ctx, "key1").Result()
	if err != nil {
		panic(err)
	}
	fmt.Println("key1 的值为:", val)

	// 初始化所有从节点连接
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

	// 随机选择一个从节点读取
	client := getSlaveClient()
	val, err = client.Get(ctx, "key1").Result()
	if err != nil {
		panic(err)
	}
	fmt.Println("key1 的值为:", val)

	masterClient = redis.NewClient(&redis.Options{
		Addr:         "172.17.0.2:6379",
		Password:     "",
		DB:           0,
		PoolSize:     20, // 连接池大小
		MinIdleConns: 5,  // 最小空闲连接数
	})

	// 带重试的写入操作
	maxRetries := 3
	for i := 0; i < maxRetries; i++ {
		err := masterClient.Set(ctx, "key", "value", 0).Err()
		if err == nil {
			break
		}
		time.Sleep(1 * time.Second)
	}

}

// 随机选择一个从节点
func getSlaveClient() *redis.Client {
	rand.Seed(time.Now().UnixNano())
	return slaveClients[rand.Intn(len(slaveClients))]
}

func SentinelRedis() {
	var (
		ctx           = context.Background()
		sentinelAddrs = []string{"172.17.0.4:26379", "172.17.0.5:26379", "172.17.0.6:26379"}
		masterName    = "mymaster"
		password      = "" // Sentinel 和 Redis 密码
	)
	// 创建 Sentinel 客户端
	sentinelClient := redis.NewSentinelClient(&redis.Options{
		Addr:     sentinelAddrs[0],
		Password: password,
	})

	// 获取当前主节点地址
	masterAddr, err := sentinelClient.GetMasterAddrByName(ctx, masterName).Result()
	if err != nil {
		panic(fmt.Sprintf("获取主节点失败: %v", err))
	}

	// 创建主节点客户端（写操作）
	masterClient := redis.NewClient(&redis.Options{
		Addr:     fmt.Sprintf("%s:%s", masterAddr[0], masterAddr[1]),
		Password: "111111",
	})

	// 创建从节点客户端（读操作）
	slaveClient := redis.NewClient(&redis.Options{
		Addr:     "172.17.0.3:6379", // 可配置多个从节点或动态获取
		Password: password,
	})

	// 写入数据到主节点
	err = masterClient.Set(ctx, "key2", "value2", 0).Err()
	if err != nil {
		panic(err)
	}

	// 从从节点读取数据
	val, err := slaveClient.Get(ctx, "key2").Result()
	if err != nil {
		panic(err)
	}
	fmt.Println("key2 的值为:", val)
}
func MasterSlave() {
	// 主节点客户端（写操作）
	masterClient := redis.NewClient(&redis.Options{
		Addr:     "localhost:16379",
		Password: "111111", // 如果有密码
		DB:       0,
	})

	// 从节点客户端（读操作）
	replicaClient := redis.NewClient(&redis.Options{
		Addr:     "localhost:26379",
		Password: "",
		DB:       0,
	})

	ctx := context.Background()

	// 写入主节点
	err := masterClient.Set(ctx, "key", "value", 0).Err()
	if err != nil {
		panic(err)
	}

	// 从从节点读取
	val, err := replicaClient.Get(ctx, "key").Result()
	if err != nil {
		panic(err)
	}
	fmt.Println("key", val)
}
