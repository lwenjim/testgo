package main

import (
	"fmt"
	"time"
)

func main() {
	str := time.Date(time.Now().Year(), time.Now().AddDate(0, 1, 0).Month(), 1, 0, 0, 0, 000, time.Local).Add(-1 * time.Second)
	fmt.Println(str.Format("2006-01-02 15:04:05"))
	fmt.Println(time.LoadLocation("Asia/Shanghai"))
}
