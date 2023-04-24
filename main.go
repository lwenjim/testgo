package main

import (
	"fmt"
	"time"
)

func main() {
	fmt.Printf("%s\n", time.Now().AddDate(0, 0, -90).Format("200601"))
}
