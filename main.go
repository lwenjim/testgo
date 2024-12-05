package main

import (
	"fmt"
	"io"
	"net/http"
)

func main() {
	resp, err := http.Get("https://www.baidu.com")
	if err != nil {
		fmt.Printf("err.Error(): %v\n", err.Error())
		return
	}
	buff, err := io.ReadAll(resp.Body)
	if err != nil {
		fmt.Printf("err.Error(): %v\n", err.Error())
		return
	}
	fmt.Printf("string(buff): %v\n", string(buff))
}
