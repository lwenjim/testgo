package main

import (
	"context"
	"log"
	"time"

	"github.com/go-redis/redis/v8"
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
