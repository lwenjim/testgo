package main

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/cr-mao/goredislock"
)

/*
续租测试，

2秒过期时间，续租时间大概是 1.33秒，10进行了7次续租，复合要求
2023/06/17 17:37:08 PONG
true
2023/06/17 17:37:10 key=test_lock_key ,续期结果:<nil>,1
2023/06/17 17:37:11 key=test_lock_key ,续期结果:<nil>,1
2023/06/17 17:37:12 key=test_lock_key ,续期结果:<nil>,1
2023/06/17 17:37:14 key=test_lock_key ,续期结果:<nil>,1
2023/06/17 17:37:15 key=test_lock_key ,续期结果:<nil>,1
2023/06/17 17:37:16 key=test_lock_key ,续期结果:<nil>,1
2023/06/17 17:37:18 key=test_lock_key ,续期结果:<nil>,1
*/
func TestRedisMain(t *testing.T) {
	s, err := miniredis.Run()
	if err != nil {
		panic(err)
	}

	// 实例化全局redisclient, 分布式锁则会用这个redisClient
	goredislock.NewRedisClient(s.Addr(), 0, "", "")

	// 1.33秒左右就会续租
	locker, ok := goredislock.NewLocker("test_lock_key", goredislock.WithContext(context.Background()), goredislock.WithExpire(time.Second*2)).Lock()
	fmt.Println(ok)
	time.Sleep(time.Second * 10)
	defer locker.Unlock()
}
