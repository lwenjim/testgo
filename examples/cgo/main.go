package main

// #cgo CFLAGS:  -I./c -I.
// #cgo LDFLAGS: -L. -L./c
// #include "mylib.c"
import "C"
import "fmt"

func main() {
	newName := C.GoString(C.print(C.CString("123")))
	fmt.Println(newName)

	var desc string
	newName = C.GoString(C.print2(C.CString(desc), C.CString("456")))
	fmt.Printf("newName: %s\n", newName)
	fmt.Printf("desc: %s\n", desc)

	fmt.Println(C.GoString(C.print3()))
	fmt.Println(C.GoString(C.print4()))
}
