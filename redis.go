package main

import (
	"context"
	"fmt"
	"log"
	"sync"
	"time"

	"github.com/go-redis/redis/v8"
)

var GlobalRedisClient *redis.Client
var redisClientOnce sync.Once

func NewRedisClient(addr string) *redis.Client {
	redisClientOnce.Do(func() {
		GlobalRedisClient = redis.NewClient(&redis.Options{
			Network:            "tcp",
			Addr:               addr,
			Password:           "",
			DB:                 0,
			PoolSize:           15,
			MinIdleConns:       10,
			DialTimeout:        5 * time.Second,
			ReadTimeout:        3 * time.Second,
			WriteTimeout:       3 * time.Second,
			PoolTimeout:        4 * time.Second,
			IdleCheckFrequency: 60 * time.Second,
			IdleTimeout:        5 * time.Minute,
			MaxConnAge:         0 * time.Second,
			MaxRetries:         0,
			MinRetryBackoff:    8 * time.Millisecond,
			MaxRetryBackoff:    512 * time.Millisecond,
		})
		pong, err := GlobalRedisClient.Ping(context.Background()).Result()
		if err != nil {
			log.Fatal(fmt.Errorf("redis connect error:%s", err))
		}
		log.Println(pong)
	})
	return GlobalRedisClient
}
