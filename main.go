package main

import (
	"fmt"
	"io"
	"net/http"
)

func main() {
	var c http.Client
	resp, err := c.Get("https://www.baidu.com")
	if err != nil {
		fmt.Printf("err: %v\n", err)
		return
	}
	defer func() { _ = resp.Body.Close() }()
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		println(err)
		return
	}
	fmt.Println(string(data))
}
