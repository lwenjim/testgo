package examples

import (
	"sync"
	"sync/atomic"
	"testing"
)

func TestAtomic(t *testing.T) {
	var count = 0
	var count2 atomic.Int32
	var wg sync.WaitGroup

	// m := map[string]int{}
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
