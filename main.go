package main

import (
	"fmt"
	"time"
)

func main() {
	{
		if time.Now().Unix() < 0 {
			fmt.Println("456")
			goto Txt
		}
	}
Txt:
	fmt.Println("123")
}
