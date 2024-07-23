package main

import (
	"fmt"
	"math/rand"
	"net/http"
	"net/url"
	"testing"
	"time"
	"unsafe"
)

func TestMain(t *testing.T) {
	http.HandleFunc("/", func(writer http.ResponseWriter, request *http.Request) {
		u, _ := url.Parse(request.URL.String())
		values, _ := url.ParseQuery(u.RawQuery)

		request_type := values.Get("type")
		request_name := values.Get("name")

		fmt.Printf("请求 %s, 开始时间 %d \r\n", request_name, time.Now().Unix())

		if request_type == "1" {
			time.Sleep(30 * time.Second)
			fmt.Printf("请求 %s, 结束时间 %d \r\n", request_name, time.Now().Unix())
		} else {
			fmt.Printf("请求 %s, 结束时间 %d \r\n", request_name, time.Now().Unix())
		}
	})
	_ = http.ListenAndServe(":9090", nil)
}

func TestSelectChannel(t *testing.T) {
	c := make(chan int)
	d := make(chan int)
	go func() {
		for i := 0; i < 10; i++ {
			c <- i
		}
		close(c)
	}()
	go func() {
		for i := 0; i < 10; i++ {
			d <- i
		}
		close(d)
	}()
	var ok, ok1 bool = true, true
	var v int
	var i int = 0
	for {
		select {
		case v, ok = <-d:
			if ok {
				fmt.Printf("v: %v, ok: %v\n", v, ok)
			} else {
				fmt.Println("d channel closed")
			}
		case v, ok1 = <-c:
			if ok1 {
				fmt.Printf("\t\t\tv1: %v, ok1: %v\n", v, ok1)
			} else {
				fmt.Println("\t\t\tc channel closed")
			}
		}
		if !ok && !ok1 {
			break
		}
		i++
	}
}

func TestUnSafe(t *testing.T) {
	type MyStruct2 struct {
		C int
	}

	type MyStruct struct {
		F byte        // 1 => 8
		A int         // 8
		B string      // 16
		D MyStruct2   // 8
		Q []MyStruct2 // 24
	}

	var s MyStruct
	s.A = 10
	s.B = "hello"
	s.D.C = 20
	_ = s.A
	_ = s.B
	fmt.Printf("Alignof: %v, Offsetof: %v, Sizeof: %v\n", unsafe.Alignof(s), unsafe.Offsetof(s.D), unsafe.Sizeof(s))
}

func TestAlignOf(t *testing.T) {
	s := struct {
		a byte  // 1
		f byte  // 1
		c byte  // 1
		d int32 // 4
		b int64 // 8
		e int64 // 8
	}{}
	_ = s
	fmt.Println(unsafe.Alignof(s))
	fmt.Println(unsafe.Sizeof(s))
	fmt.Println("")
	fmt.Println("a:", unsafe.Offsetof(s.a))
	fmt.Println("f:", unsafe.Offsetof(s.f))
	fmt.Println("c:", unsafe.Offsetof(s.c))
	fmt.Println("d:", unsafe.Offsetof(s.d))
	fmt.Println("b:", unsafe.Offsetof(s.b))
	fmt.Println("e:", unsafe.Offsetof(s.e))
}

func TestEscape(t *testing.T) {
	generate8191 := func() {
		nums := make([]int, 8191) // < 64KB
		for i := 0; i < 8191; i++ {
			nums[i] = rand.Int()
		}
	}

	generate8192 := func() {
		nums := make([]int, 8193) // = 64KB
		for i := 0; i < 8193; i++ {
			nums[i] = rand.Int()
		}
	}

	generate := func(n int) {
		nums := make([]int, n) // 不确定大小
		for i := 0; i < n; i++ {
			nums[i] = rand.Int()
		}
	}
	generate8191()
	generate8192()
	generate(1)
}
