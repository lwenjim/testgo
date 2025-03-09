package main

import "jspp/testgo/cmd"

func main() {
	// fmt.Println(time.Unix(1739003234, 0).Format("2006:01-02 15:04:05"))
	// 2024-12-16 08:26:00
	// updateTime, _ := time.ParseInLocation("2006-01-02 15:04:05", "2024-12-16 08:26:00", time.Local)
	// fmt.Printf("updateTime: %v\n", updateTime.Unix())
	cmd.Exec()
}
