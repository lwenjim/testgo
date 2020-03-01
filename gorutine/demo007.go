package main

//互斥锁
import (
	"fmt"
	"runtime"
	"sync"
)

var (
	counter7 int
	wg7      sync.WaitGroup
	mutex    sync.Mutex
)

func main() {
	wg7.Add(3)

	go incCounter7(1)
	go incCounter7(2)
	go incCounter7(3)

	wg7.Wait()
	fmt.Printf("Final counter7: %d\n", counter7)
}

func incCounter7(id int) {
	defer wg7.Done()

	for count := 0; count < 2; count++ {
		mutex.Lock()
		{
			value := counter7
			runtime.Gosched()
			value++
			counter7 = value
		}
		mutex.Unlock()
	}
}
