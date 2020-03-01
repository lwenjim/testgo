package main

import (
	"fmt"
	"runtime"
	"strconv"
	"time"
)

func main() {
	runtime.GOMAXPROCS(1)
	ch := make(chan int)
	go func() {
		for i := 0; i < 10; i++ {
			if i == 5 {
				<- ch
			}
			fmt.Println("gorutine 1 i:" + strconv.Itoa(i))
		}
	}()

	go func() {
		for i := 10; i < 20; i++ {
			fmt.Println("gorutine 2 i:" + strconv.Itoa(i))
		}
		ch <- 1
	}()
	time.Sleep(time.Second)
}
