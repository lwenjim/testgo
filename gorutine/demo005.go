package main

import (
	"fmt"
	"runtime"
	"sync"
	"sync/atomic"
)

var (
	counter2 int64
	wg3      sync.WaitGroup
)

func main() {
	wg3.Add(2)

	go incCounter3(1)
	go incCounter3(2)

	wg3.Wait()

	fmt.Println("Final counter2:", counter2)
}

func incCounter3(id int) {
	defer wg3.Done()
	for count := 0; count < 2; count++ {
		atomic.AddInt64(&counter2, 1)
		runtime.Gosched()
	}
}
