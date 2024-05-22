package main

import (
	"github.com/cheggaaa/pb/v3"
	"time"
)

func main() {
	// 创建一个新的进度条，设置总数为100
	count := 100
	bar := pb.StartNew(count)

	// 模拟任务，并不断更新进度条
	for i := 0; i < count; i++ {
		// 模拟任务执行
		time.Sleep(time.Millisecond * 50)

		// 更新进度条
		bar.Increment()
	}

	// 完成任务，停止进度条
	bar.Finish()
}
