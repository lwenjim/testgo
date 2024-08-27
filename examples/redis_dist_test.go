package examples

import (
	"context"
	"fmt"
	"log"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/go-redis/redis/v8"
	"github.com/stretchr/testify/assert"
)

const defaultExpireTime = time.Second * 10

type Locker struct {
	key        string
	unlock     bool
	incrScript *redis.Script
	option     options
}

type Options func(o *options)

type options struct {
	expire      time.Duration
	redisClient *redis.Client
	ctx         context.Context
}

var GlobalRedisClient *redis.Client
var redisClientOnce sync.Once

func NewRedisClient(addr string) *redis.Client {
	option := &redis.Options{
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
	}
	redisClientOnce.Do(func() {
		GlobalRedisClient = redis.NewClient(option)
		pong, err := GlobalRedisClient.Ping(context.Background()).Result()
		if err != nil {
			log.Fatal(fmt.Errorf("redis connect error:%s", err))
		}
		log.Println(pong)
	})
	return GlobalRedisClient
}

const incrLua = `
if redis.call('get', KEYS[1]) == ARGV[1] then
  return redis.call('expire', KEYS[1],ARGV[2])
 else
   return '0'
end`

func NewLocker(key string, opts ...Options) *Locker {
	var lock = &Locker{
		key:        key,
		incrScript: redis.NewScript(incrLua),
	}
	for _, opt := range opts {
		opt(&lock.option)
	}
	if lock.option.expire == 0 {
		lock.option.expire = defaultExpireTime
	}
	if lock.option.redisClient == nil {
		lock.option.redisClient = GlobalRedisClient
	}
	if lock.option.ctx == nil {
		lock.option.ctx = context.Background()
	}
	return lock
}

func WithExpire(expire time.Duration) Options {
	return func(o *options) {
		o.expire = expire
	}
}

func WithRedisClient(redisClient *redis.Client) Options {
	return func(o *options) {
		o.redisClient = redisClient
	}
}

func WithContext(ctx context.Context) Options {
	return func(o *options) {
		o.ctx = ctx
	}
}

func (l *Locker) Lock() (*Locker, bool) {
	boolcmd := l.option.redisClient.SetNX(context.Background(), l.key, "1", l.option.expire)
	if ok, err := boolcmd.Result(); err != nil || !ok {
		return l, false
	}
	l.expandLockTime()
	return l, true
}

func (l *Locker) expandLockTime() {
	sleepTime := l.option.expire * 2 / 3
	go func() {
		for {
			time.Sleep(sleepTime)
			if l.unlock {
				break
			}
			l.resetExpire()
		}
	}()
}

func (l *Locker) resetExpire() {
	cmd := l.incrScript.Run(l.option.ctx, l.option.redisClient, []string{l.key}, 1, l.option.expire.Seconds())
	v, err := cmd.Result()
	log.Printf("key=%s ,续期结果:%v,%v\n", l.key, err, v)
}

func (l *Locker) Unlock() {
	l.unlock = true
	l.option.redisClient.Del(l.option.ctx, l.key)
}
func TestLocker_Lock(t *testing.T) {
	s, err := miniredis.Run()
	assert.Nil(t, err)

	var w sync.WaitGroup
	for i := 0; i < 10; i++ {
		w.Add(1)
		go func(i int) {
			defer w.Done()
			client := NewRedisClient(s.Addr())
			lock := NewLocker("abc", WithRedisClient(client))
			for {
				l, ok := lock.Lock()
				if ok {
					fmt.Printf("l.key: %v, index: %v\n", l.key, i)
					lock.Unlock()
					break
				}
				time.Sleep(100 * time.Microsecond)
			}
		}(i)
	}
	w.Wait()
}

func TestLocker_Lock2(t *testing.T) {
	s, err := miniredis.Run()
	assert.Nil(t, err)

	c := make(map[int]chan struct{}, 10)
	for i := 0; i < 10; i++ {
		c[i] = make(chan struct{})
		go func(i int) {
			defer func() {
				c[i] <- struct{}{}
			}()
			client := NewRedisClient(s.Addr())
			lock := NewLocker("abc", WithRedisClient(client))
			for {
				l, ok := lock.Lock()
				if ok {
					fmt.Printf("l.key: %v, index: %v\n", l.key, i)
					lock.Unlock()
					break
				}
				time.Sleep(100 * time.Microsecond)
			}
		}(i)
	}
	for i := 0; i < 10; i++ {
		<-c[i]
	}
}

func TestLocker_Lock3(t *testing.T) {
	total := 12
	var num int32
	log.Println("begin")
	ctx, cancelFunc := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancelFunc()
	for i := 0; i < total; i++ {
		go func() {
			time.Sleep(3 * time.Second)
			atomic.AddInt32(&num, 1)
			if atomic.LoadInt32(&num) == 10 {
				cancelFunc()
			}
		}()
	}
	for i := 0; i < 5; i++ {
		go func() {
			<-ctx.Done()
			log.Println("ctx1 done", ctx.Err())

			for i := 0; i < 2; i++ {
				go func() {
					<-ctx.Done()
					log.Println("ctx2 done", ctx.Err())
				}()
			}
		}()
	}

	time.Sleep(time.Second * 10)
	log.Println("end", ctx.Err())
	fmt.Printf("执行完毕 %v\n", num)
}

func TestNewRedisClient(t *testing.T) {
	s, err := miniredis.Run()
	assert.Nil(t, err)
	client := NewRedisClient(s.Addr())
	client.Set(context.Background(), "abc", 123, 86400)
	res, err := client.Get(context.Background(), "abc").Result()
	assert.Nil(t, err)
	assert.True(t, res == "123")
}
