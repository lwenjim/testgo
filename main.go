package main

// #include "mylib.h"
import "C"
import "fmt"

func main() {
	newName := C.GoString(C.print(C.CString("123")))
	fmt.Println(newName)

	var desc string
	newName = C.GoString(C.print2(C.CString(desc), C.CString("456")))
	fmt.Println(newName)

	fmt.Println(C.GoString(C.print3()))

	fmt.Println(C.GoString(C.print4()))
}
