package main

import (
	"bytes"
	"fmt"
	"os/exec"
)

func main() {
	cmd := exec.Command("ls")
	var out bytes.Buffer
	cmd.Stdout = &out
	if err := cmd.Run(); err != nil {
		fmt.Printf("err: %v\n", err)
		return
	}
	fmt.Printf("out.String(): %v\n", out.String())
}
