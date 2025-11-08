package main

func main() {
	go func() {
		go func() {
			panic("111")
		}()
	}()
}
