package main

import (
	"context"
	"fmt"
	"log"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/stretchr/testify/assert"
)

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
