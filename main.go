package main

import (
	"fmt"
	"path/filepath"
	"reflect"
	"runtime"
)

type MyStruct struct{}

func (m *MyStruct) MyMethod() {}

// GetMethodLocation 获取方法定义的文件和行号
func GetMethodLocation(obj interface{}, methodName string) (file string, line int, err error) {
	// 获取方法的反射值
	method := reflect.ValueOf(obj).MethodByName(methodName)
	if !method.IsValid() {
		return "", -1, fmt.Errorf("方法不存在")
	}

	// 获取方法的函数指针
	pc := method.Pointer()
	if pc == 0 {
		return "", -1, fmt.Errorf("无法获取函数指针")
	}

	// 通过函数指针获取运行时信息
	funcInfo := runtime.FuncForPC(pc)
	if funcInfo == nil {
		return "", -1, fmt.Errorf("无法获取函数信息")
	}

	// 解析文件名和行号
	file, line = funcInfo.FileLine(pc)
	return filepath.Base(file), line, nil
}

func main() {
	obj := &MyStruct{}
	file, line, err := GetMethodLocation(obj, "MyMethod")
	if err != nil {
		fmt.Println("错误:", err)
		return
	}
	fmt.Printf("方法定义位置: %s:%d\n", file, line) // 输出示例: main.go:13
}
