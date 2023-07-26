package main

import (
	"fmt"
	"time"
)

func main() {
	loc, err := time.LoadLocation("GMT-8")
	if err != nil {
		fmt.Println(err)
		return
	}
	fmt.Println(time.Now().Location())
	fmt.Println(time.Now().Local().Location())
	fmt.Println(time.Now().UTC().Location())
	fmt.Println(loc)

	fmt.Println(time.Now().In(loc).Format("2006-01-02 15:04:05"))
}
