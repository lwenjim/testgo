package main

import "fmt"

type Perso4 struct {
	name string
	sex  string
	age  int
}

func (p *Perso4) PrintInfoPointer() {
	//%p是地址，%v是值
	fmt.Printf("%p,%v\n", p, p)
}

func main() {
	p := Perso4{"zhangsan", "male", 18}
	//传统调用方式
	p.PrintInfoPointer()
	//go语义方法值特性
	pFunc1 := p.PrintInfoPointer
	pFunc1()
	//go方法表达式特性
	pFunc2 := (*Perso4).PrintInfoPointer
	pFunc2(&p)
}