package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	_ "net/http/pprof"
	"time"
)

var tz *time.Location

func main() {
	go func() {
		for {
			LocalTz()

			doSomething([]byte(`{"a": 1, "b": 2, "c": 3}`))
		}
	}()

	fmt.Println("start api server...")
	panic(http.ListenAndServe(":8080", nil))
}

// func doSomething(s []byte) {
// 	var m map[string]interface{}
// 	err := json.Unmarshal(s, &m)
// 	if err != nil {
// 		panic(err)
// 	}

// 	s1 := make([]string, 0)
// 	s2 := ""
// 	for i := 0; i < 100; i++ {
// 		s1 = append(s1, string(s))
// 		s2 += string(s)
// 	}
// }

func doSomething(s []byte) {
	var m map[string]interface{}
	err := json.Unmarshal(s, &m)
	if err != nil {
		panic(err)
	}

	s1 := make([]string, 0, 100)
	var buff bytes.Buffer
	for i := 0; i < 100; i++ {
		s1 = append(s1, string(s))
		buff.Write(s)
	}
}

// func doSomething(s []byte) {
// 	var m map[string]interface{}
// 	err := json.Unmarshal(s, &m)
// 	if err != nil {
// 		panic(err)
// 	}

// 	s1 := make([]string, 0)
// 	var buff bytes.Buffer
// 	for i := 0; i < 100; i++ {
// 		s1 = append(s1, string(s))
// 		buff.Write(s)
// 	}
// }

func LocalTz() *time.Location {
	if tz == nil {
		tz, _ = time.LoadLocation("Asia/Shanghai")
	}
	return tz
}
