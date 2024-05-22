package main

import (
	"fmt"
	"net/http"
	"net/url"
	"testing"
	"time"
)

func TestMain(t *testing.T) {
	http.HandleFunc("/", func(writer http.ResponseWriter, request *http.Request) {
		u, _ := url.Parse(request.URL.String())
		values, _ := url.ParseQuery(u.RawQuery)

		request_type := values.Get("type")
		request_name := values.Get("name")

		fmt.Printf("请求 %s, 开始时间 %d \r\n", request_name, time.Now().Unix())

		if request_type == "1" {
			time.Sleep(30 * time.Second)
			fmt.Printf("请求 %s, 结束时间 %d \r\n", request_name, time.Now().Unix())
		} else {
			fmt.Printf("请求 %s, 结束时间 %d \r\n", request_name, time.Now().Unix())
		}
	})
	_ = http.ListenAndServe(":9090", nil)
}
