package main

import "fmt"

func main() {
<<<<<<< HEAD
	time.Local = time.FixedZone("CST", 8*3600)
	loc2, _ := time.LoadLocation("Asia/Shanghai")
	// d, _ := time.ParseInLocation("2006-01-02 15:04:05", "2024-05-21 9:41:24", time.Local)
	// fmt.Printf("%f, \t %v\n", time.Now().In(time.Local).Sub(d).Seconds(), time.Now())
	d, _ := time.ParseInLocation("2006-01-02 15:04:05", "2024-05-21 11:00:24", time.Local)
	fmt.Printf("%f, \t %v\n", time.Now().In(loc2).Sub(d).Seconds(), time.Now())
=======
	m := make(chan int)
	go func() {
		for i := 0; i < 10; i++ {
			m <- i
		}
		close(m)
	}()
	for v := range m {
		fmt.Println(v)
	}
>>>>>>> 6bb84f2172ac498843462bbc3150bf510c348af7
}
