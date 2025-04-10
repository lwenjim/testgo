package main

import (
    "fmt"
    "reflect"
)

// 示例结构体
type MyStruct struct{}

// 值接收者方法
func (m MyStruct) ValueMethod() {}

// 指针接收者方法
func (m *MyStruct) PointerMethod() {}

// 检查结构体是否包含方法（含指针接收者）
func HasMethods(s interface{}) bool {
    // 获取类型和指针类型
    typeOf := reflect.TypeOf(s)
    ptrType := reflect.PtrTo(typeOf)

    // 检查值类型和指针类型的方法总数
    return typeOf.NumMethod()+ptrType.NumMethod() > 0
}

func main() {
    // 测试值类型
    var s MyStruct
    fmt.Println("MyStruct 是否有方法:", HasMethods(s)) // 输出: true

    // 测试指针类型
    var p *MyStruct
    fmt.Println("*MyStruct 是否有方法:", HasMethods(p)) // 输出: true

    // 测试无方法的结构体
    type EmptyStruct struct{}
    fmt.Println("EmptyStruct 是否有方法:", HasMethods(EmptyStruct{})) // 输出: false
}