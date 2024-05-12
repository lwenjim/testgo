package main

import "fmt"

func main() {
	m := make(chan int)
	go func() {
		for i := 0; i < 10; i++ {
			m <- i
		}
		close(m)
	}()
	for v := range m {
		fmt.Println(v)
	}
}
