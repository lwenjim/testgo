package main

import "fmt"

type Student struct {
	id   int
	name string
	sex  string
	age  int
	addr string
}

func tmpStudent(tmp Student) {
	tmp.id = 250
	fmt.Println("tmp=", tmp) //tmp= {250 zhangsan f 20 sz00}
}
func tmpStudent2(p *Student) {
	p.id = 249
	fmt.Println("tmp=", p) //tmp= &{249 zhangsan f 20 sz00}
}
func main() {
	var s Student = Student{1, "zhangsan", "f", 20, "sz00"}
	//传递非指针对象
	tmpStudent(s)
	fmt.Println("main s=", s) //main s= {1 zhangsan f 20 sz00}
	//传递指针对象
	tmpStudent2(&s)
	fmt.Println("main s2=", s) // main s2= {249 zhangsan f 20 sz00}
}
