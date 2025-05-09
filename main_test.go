package main

import (
	"fmt"
	"os"
	"testing"
)

func TestMain(t *testing.T) {
	fmt.Printf("os.Getenv(\"GOWORK\"): %v\n", os.Getenv("GOWORK"))
}
