package main

import "fmt"

func main() {
	a := func(x, y int) int { return x + y }(3, 4)
	fmt.Println(a)
}
