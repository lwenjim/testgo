package main

import "time"

func main() {
	for i := 0; i < 10; i++ {
		go func() {
			time.Sleep(3 * time.Second)
		}()
	}
	go func() {
		for {
			time.Sleep(1 * time.Second)
		}
	}()
	select {}

}
