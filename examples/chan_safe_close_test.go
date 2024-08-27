package examples

import (
	"context"
	"fmt"
	"sync"
	"time"
)

func TestChanSafeClose() {
	c := make(chan int, 10)
	wg := sync.WaitGroup{}
	ctx, cancel := context.WithCancel(context.TODO())
	go func() {
		time.Sleep(2 * time.Second)
		cancel()
		close(c)
	}()
	for i := 0; i < 10; i++ {
		go func(ctx context.Context, id int) {
			select {
			case <-ctx.Done():
				return
			case c <- id:
				fmt.Println(123)
			}
		}(ctx, i)
	}
	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for v := range c {
				_ = v
			}
		}()
	}
	wg.Wait()
}

// 安全关闭channel 方法一
func SafeClose(ch chan int) (closed bool) {
	defer func() {
		if recover() != nil {
			closed = false
		}
	}()
	close(ch)
	return true
}

// 安全关闭channel 方法二
// sync.Once 保证只执行一次
type ChanMrg struct {
	C    chan int
	once sync.Once
}

func NewChanMgr() *ChanMrg {
	return &ChanMrg{C: make(chan int)}
}

func (cm *ChanMrg) SafeClose() {
	cm.once.Do(func() {
		close(cm.C)
	})
}
