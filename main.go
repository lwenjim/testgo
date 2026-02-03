package main

import (
	"fmt"
	"os/exec"
)

func main() {
	if output, err := exec.Command(`D:\workdata\testgo\csharp\ManageAnonTokyo\bin\Debug\ManageAnonTokyo.exe`).Output(); err != nil {
		fmt.Println(err)
	} else {
		fmt.Println(string(output))
	}
}
