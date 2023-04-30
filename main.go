package main

import (
	"bytes"
	"io"
	"net/http"
)

func main() {
	buf := bytes.NewBufferString("")
	resp, err := http.Post("http://www.baidu.com", "application/json", buf)
	if err != nil {
		println(err)
	} else {
		defer resp.Body.Close()
		buff, err := io.ReadAll(resp.Body)
		if err != nil {
			println(err)
		} else {
			println(string(buff))
		}
	}
}
