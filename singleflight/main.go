// https://github.com/chenmingyong0423/blog/blob/master/tutorial-code/go/singleflight/usage/main.go
package main

import (
	"errors"
	"fmt"
	"sync"

	"golang.org/x/sync/singleflight"
)

var errRedisKeyNotFound = errors.New("redis: key not found")

func fetchDataFromCache() (any, error) {
	fmt.Println("fetch data from cache")
	return nil, errRedisKeyNotFound
}

func fetchDataFromDataBase() (any, error) {
	fmt.Println("fetch data from database")
	return "程序员陈明勇", nil
}

func fetchData() (any, error) {
	cache, err := fetchDataFromCache()
	if err != nil && errors.Is(err, errRedisKeyNotFound) {
		fmt.Println(errRedisKeyNotFound.Error())
		return fetchDataFromDataBase()
	}
	return cache, err
}

func main() {
	newFunction()
}

func newFunction() {
	var (
		sg singleflight.Group
		wg sync.WaitGroup
	)

	for i := 0; i < 5; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			v, err, shared := sg.Do("key", fetchData)
			if err != nil {
				panic(err)
			}
			fmt.Printf("v: %v, shared: %v\n", v, shared)
		}()
	}
	wg.Wait()
}
