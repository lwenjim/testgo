package main

import (
	"fmt"
	"runtime"
	"runtime/debug"
)

func main() {
	go func() {
		// 普通 goroutine
		debug.PrintStack()
	}()
	runtime.Gosched()
	// 查看当前协程信息
	fmt.Printf("Is g0? %t\n", isG0())

}

// 检测当前是否在 g0
func isG0() bool {
	return runtime.GOROOT() == "" // g0 无 GOROOT 信息
}
