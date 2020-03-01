package main

//一般函数
func Run1(a int) {
	println(a)
}

//多参数，无返回值
func Run2(a, b int, c string) {
	println(a, b, c)
}

//单个返回值
func Run3(a, b int) int { //同类型，可以省略  a, b int
	return a + b
}

//多个返回值
func Run4(a, b int) (c int, err error) {  //返回值还可以是   (int, error)
	return a+b, nil
}

func Run5(A, B int) (int, int) {
	return A+B, A*B
}