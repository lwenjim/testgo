package main

import (
	"fmt"
)

func main() {
	ch := make(chan int, 10)

	ch <- 111
	ch <- 333
	close(ch)
	for value := range ch {
		fmt.Println(value)
	}

	x, ok := <- ch
	fmt.Println(x, ok)
}
