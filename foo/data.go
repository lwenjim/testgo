package foo

import "fmt"

type Programmer struct {
	name     string
	age      int
	language string
}

func InitProgrammer() *Programmer {
	return &Programmer{"stefno", 18, "go"}
}

type TestPointer struct {
	A int
	b int // 私有变量
	c string
	d int
}

func (T *TestPointer) OouPut() {
	fmt.Println("TestPointer OouPut:", T.A, T.b, T.c, T.d)
}
