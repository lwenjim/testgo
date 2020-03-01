package main

import "fmt"

type Person struct {
	name string
	sex  string
	age  int
}

//给成员赋值，引用语义
func (p *Person) SetInfoPointer() {
	(*p).name = "tianqi"
	p.sex = "female"
	p.age = 22
}

//值语义
func (p Person) SetInfoValue() {
	p.name = "zhouba"
	p.sex = "male"
	p.age = 25
}
func main() {
	//指针作为接收者的效果
	p1 := Person{"xxx", "male", 18}
	fmt.Println("函数调用前=", p1)
	(&p1).SetInfoPointer()
	fmt.Println("函数调用后=", p1)

	//值作为接收者
	p2 := Person{"yyy", "female", 30}
	fmt.Println("函数调用前=", p2)
	p2.SetInfoValue()
	fmt.Println("函数调用后=", p2)
}
