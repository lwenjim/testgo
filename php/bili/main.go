package main

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/gin-gonic/gin"
)

func RunPowerShell(script string) (string, error) {
	cmd := exec.Command("powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	output := strings.TrimSpace(stdout.String())
	if err != nil {
		return output, fmt.Errorf("PowerShell执行错误: %v\nStderr: %s", err, stderr.String())
	}
	return output, nil
}

func RunPowerShellFile(filePath string, args ...string) (string, error) {
	cmdArgs := []string{"-NoProfile", "-ExecutionPolicy", "Bypass", "-File", filePath}
	cmdArgs = append(cmdArgs, args...)
	cmd := exec.Command("powershell", cmdArgs...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	output := strings.TrimSpace(stdout.String())
	if err != nil {
		return output, fmt.Errorf("PowerShell文件执行错误: %v\nStderr: %s", err, stderr.String())
	}
	return output, nil
}

func ExecPowerShell() string {
	filename := "D:\\workdata\\testgo\\php\\bili\\start.ps1"
	if _, err := os.Stat(filename); err == nil {
		output, _ := RunPowerShellFile(filename)
		return output
	}
	return ""
}

func main() {
	router := gin.Default()
	router.GET("/deploy", func(c *gin.Context) {
		if output, err := exec.Command(`D:\workdata\testgo\csharp\ManageAnonTokyo\bin\Debug\ManageAnonTokyo.exe`).Output(); err != nil {
			c.String(500, err.Error())
		} else {
			c.String(200, string(output))
		}
		// output := ExecPowerShell()
	})
	if err := router.Run(":8081"); err != nil {
		fmt.Println(err)
	}
}
