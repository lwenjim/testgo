package main

import (
	"sync"
	"sync/atomic"
)

func main() {
	var a = func() (a int) {
		defer func() {
			a = 2
		}()
		return 1
	}()
	println(a)

	var count = 0
	var count2 atomic.Int32
	var wg sync.WaitGroup
	for i := 0; i < 10000; i++ {
		wg.Add(1)
		go func() {
			for j := 0; j < 10; j++ {
				count++
				count2.Add(1)
			}
			wg.Done()
		}()
	}
	wg.Wait()
	println(count)
	println(count2.Load())
}
