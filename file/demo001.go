package main

import (
	"fmt"
	"io"
	"io/ioutil"
	"net"
	"os"
)

func main() {
	//test2("1", "2", "3")
	//s := []interface{}{3, 5, 1, 4, 2}
	//test2(s[0], s...);

	a := [...]int{0, 1, 2, 3, 4, 5, 6}
	b := make([]int, 2, 4)
	c := a[1:]
	b = append(b, c...)
	d:=make([]int, 2, 4);
	e:="你"
	f := []byte(e)
	g:=[]rune(e)
	copy(d, c);
	var m1 map[int]string
	fmt.Println(nil==m1)
	m2 := map[int]string{}
	fmt.Println(m2)
	m3 :=make(map[int]string)
	fmt.Println(m3)
	m4 :=make(map[int]string, 10)
	fmt.Println(m4)
	fmt.Println(m4[1])
	fmt.Printf("%v\n", a)
	fmt.Printf("%v\n", b)
	fmt.Printf("%v\n", d[:])
	fmt.Printf("%v\n", f)
	fmt.Printf("%v\n", g)
	ma:=map[int]string{1:"a", 2:"b"}
	fmt.Println(ma[1])
}

func test2(first interface{}, str ...interface{}) {
	test3(first, str...);
}
func test3(first interface{}, str ...interface{}) interface{} {
	min := first
	for _, value := range str {
		switch value := value.(type) {
		case int:
			if value < min.(int) {
				min = value
			}
		case float64:
			if value < min.(float64) {
				min = value

			}
		case float32:
			if value < min.(float32) {
				min = value
			}
		case string:
			if value < min.(string) {
				min = value
			}
		}
	}
	return min
}

func test() () {
	addr, err := net.LookupHost("www.baidu.com")
	if err, ok := err.(*net.DNSError); ok {
		if err.Timeout() {
			fmt.Println("operation timed out")
		} else if err.Temporary() {
			fmt.Println("temporary error")
		} else {
			fmt.Println("generic error: ", err)
		}
	}
	fmt.Println(addr)
}

func Read0() (string) {
	f, err := ioutil.ReadFile("go.mod1")
	if err != nil {
		fmt.Println("", err)
		return ""
	}
	print("12323")
	return string(f)
}

func Read1() (string) {
	f, err := os.Open("go.mod")
	if err != nil {
		fmt.Println("read fail")
		return ""
	}
	defer f.Close()
	var chunk []byte
	buf := make([]byte, 1024)
	for {
		n, err := f.Read(buf)
		if err != nil && err != io.EOF {
			fmt.Println("read buf fail", err)
			return ""
		}
		if n == 0 {
			break
		}
		chunk = append(chunk, buf[:n]...)
	}
	return string(chunk)
}
