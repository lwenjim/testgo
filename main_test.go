package main

import (
	"fmt"
	"testing"
)

func TestMain(m *testing.M) {
	m.Run()
}

func Test_aa(t *testing.T) {
	name := 123
	fmt.Printf("name: %v\n", name)
}
