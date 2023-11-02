package main

import "fmt"

func main() {
	name := test()
	fmt.Println(name())

	ch := make(chan int, 1)
	ch <- 1
	close(ch)
	fmt.Println(<-ch)
	// close(ch)
}

func test() func() string {
	return func() string {
		return "后端时光"
	}
}
