package main

//static const char* cs = "hello";
import "C"
import "Helper/helper"

func main() {
	helper.PrintCString(C.cs)
}
