package main

import "fmt"

type Myint int

//定义方法，实现两个数相加
func Add(a, b Myint) Myint {
	return a + b
}
func (a Myint) Add(b Myint) Myint {
	return a + b
}
func main() {
	var a Myint = 1
	var b Myint = 1
	//面向过程调用
	fmt.Println("Add(a,b)", Add(a, b)) //Add(a,b) 2
	//面向对象的调用
	fmt.Println("a.Add(b)", a.Add(b)) //a.Add(b) 2
}
