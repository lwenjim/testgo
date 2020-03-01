package main

import "fmt"

type Person2 struct {
	name string
	sex  string
	age  int
}

//为Person定义方法
func (p *Person2) PrintInfo() {
	fmt.Printf("%s,%s,%d\n", p.name, p.sex, p.age)
}

//继承上面的方法
type Student struct {
	Person2
	id   int
	addr string
}

func main() {
	p := Person2{"xxx", "male", 20}
	p.PrintInfo()
	s := Student{Person2{"yyy", "male", 20}, 1, "bj"}
	s.Person2 =Person2{name:"lwenjin", age:33}
	s.PrintInfo()
}