package examples

import (
	"fmt"
	"testing"
	"time"
)

func TestChanIsClose(t *testing.T) {
	c := make(chan int)
	go func() {
		c <- 0
		time.Sleep(time.Second * 4)
	}()
	go func() {
		time.Sleep(time.Second * 3)
		<-c
		fmt.Printf("%t\n", IsChanClosed2(c))
	}()
	time.Sleep(time.Second * 5)
}

// 判断channel是否已关闭方法二
func IsChanClosed2(ch chan int) bool {
	select {
	case _, received := <-ch:
		return !received
	default:
	}
	return false
}
