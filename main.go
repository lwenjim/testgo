package main

import "fmt"

func main() {
	m := map[int]string{
		1: "a",
		2: "b",
	}
	for i, v := range m {
		fmt.Printf("i: %v\n", i)
		fmt.Printf("v: %v\n", v)
	}
}
