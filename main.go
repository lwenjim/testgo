package main

import (
	"fmt"
	"net/url"
	"time"
)

func main() {
	loc, _ := time.LoadLocation("Asia/Shanghai")
	fmt.Println(url.QueryEscape(loc.String()))
}
