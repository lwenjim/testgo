package main

import (
	"fmt"
	"sync"
)

func main() {
	m := make([]sync.Map, 60)
	m[0].Store("abc", "123")
	m[0].Range(func(key, value any) bool {
		k, _ := key.(string)
		v, _ := value.(string)
		fmt.Printf("%s, %s\n", k, v)
		return true
	})
}
