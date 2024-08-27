package main

import (
	"fmt"
	"math/rand"
)

func main() {
	a := rand.Int()
	b := rand.Int()
	switch {
	case a > b:
		fmt.Println(1)
	case b > a:
		fmt.Println(2)
	}
}
