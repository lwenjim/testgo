package main

import (
	"fmt"

	"github.com/bitly/go-simplejson"
)

func main() {
	js, _ := simplejson.NewJson([]byte(`{"authToken":"abc"}`))
	fmt.Printf("js.Get(\"authToken\"): %v\n", js.Get("authToken"))
}
