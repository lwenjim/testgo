package main

import (
	"fmt"
	"testing"
)

func TestMain(t *testing.T) {
	var s []int
	for _, v := range s {
		fmt.Println(v)
	}
	fmt.Printf("s: %v\n", s == nil)
}
