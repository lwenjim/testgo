package oop

import "fmt"

type Person3 struct {
	name string
	sex  string
	age  int
}

//为Person3定义方法
func (p *Person3) PrintInfo() {
	fmt.Printf("%s,%s,%d\n", p.name, p.sex, p.age)
}

//继承上面的方法
type Studen2 struct {
	Person3
	id   int
	addr string
}

//相当于实现了方法重写
func (s *Studen2) PrintInfo() {
	fmt.Printf("Studen2:%s,%s,%d\n", s.name, s.sex, s.age)
}

func main() {
	p := Person3{"xxx", "male", 20}
	p.PrintInfo()
	s := Studen2{Person3{"yyy", "male", 20}, 1, "bj"}
	s.PrintInfo()
	//显式调用
	s.Person3.PrintInfo()
}
