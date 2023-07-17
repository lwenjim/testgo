package main

import (
	"fmt"
	"time"
)

func main() {

	var i int = 0
	go func() {
		for {
			i++
			fmt.Println("subroutine: i = ", i)
			time.Sleep(1 * time.Second)
		}
	}()
	for {
		i++
		fmt.Println("mainroutine: i = ", i)
		time.Sleep(1 * time.Second)
	}
}

func Foo() {
	println(123)
}
