package main

import (
	"fmt"
	"sync"
	"time"
)

func main() {
	var num int32
	var w sync.WaitGroup
	start := time.Now()
	for i := 0; i < 100000; i++ {
		num++
		fmt.Printf("num: %v\n", num)
	}
	w.Wait()
	fmt.Printf("%+v\n", time.Since(start).Seconds())
	fmt.Printf("%+v\n", "done")
}
