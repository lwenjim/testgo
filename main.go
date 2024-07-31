package main

import (
	"fmt"
	"reflect"
)

type Person struct {
	Name string `json:"name"`
	Age  NewInt `json:"age"`
	sex  string `json:"sex"`
}

type (
	NewInt uint32
)

func main() {
	var data = &Person{"lwenjim", 11, "aaa"}
	d_ref := reflect.ValueOf(*data)
	_, ok := d_ref.Field(1).Interface().(uint32)
	fmt.Printf("ok: %v\n", ok)

	var a uint64 = 11
	fmt.Printf("a: %T\n", a)
	fmt.Println(reflect.TypeOf(a))
}

func equZeroValue[T int32](val T) {

}
