package main

import (
	"fmt"
)

func main() {
	a := "abc"
	fmt.Println(a[len(a)-1:])
}
