package main

import (
	"fmt"
	"log"
	"net/http"
)

func main() {
	h := make(handler)
	go counter(h)
	if err := http.ListenAndServe(":8000", h); err != nil {
		log.Print(err)
	}
	type Person struct {
		Name string `json:"name"`
		Age  int32  `json:"age"`
	}
	var a = Person{
		Name: "",
		Age:  0,
	}

}

func counter(ch chan<- int) {
	for n := 0; ; n++ {
		ch <- n
	}
}

type handler chan int

func (h handler) ServeHTTP(w http.ResponseWriter, req *http.Request) {
	w.Header().Set("Content-type", "text/plain")
	fmt.Fprintf(w, "%s: you are visitor #%d", req.URL, <-h)
}
