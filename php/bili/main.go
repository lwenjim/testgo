package main

import (
	"bytes"
	"fmt"
	"log"
	"os"
	"os/exec"
	"strings"

	"github.com/gin-gonic/gin"
)

// 基础PowerShell执行函数
func RunPowerShell(script string) (string, error) {
	// 构建PowerShell命令
	cmd := exec.Command("powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script)

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	// 执行命令
	err := cmd.Run()

	output := strings.TrimSpace(stdout.String())
	if err != nil {
		return output, fmt.Errorf("PowerShell执行错误: %v\nStderr: %s", err, stderr.String())
	}

	return output, nil
}

// 执行PowerShell脚本文件
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

func main2() {
	// // 示例1: 执行简单命令
	// output, err := RunPowerShell("Write-Host 'Hello from PowerShell'; Get-Date -Format 'yyyy-MM-dd HH:mm:ss'")
	// if err != nil {
	// 	log.Fatalf("命令执行失败: %v", err)
	// }
	// fmt.Printf("输出: %s\n", output)

	// // 示例2: 获取系统信息
	// sysInfo, err := RunPowerShell(`
	//     $info = @{
	//         ComputerName = $env:COMPUTERNAME
	//         UserName = $env:USERNAME
	//         OSVersion = [System.Environment]::OSVersion.VersionString
	//         ProcessCount = (Get-Process).Count
	//     }
	//     $info | ConvertTo-Json
	// `)
	// if err != nil {
	// 	log.Fatalf("获取系统信息失败: %v", err)
	// }
	// fmt.Printf("系统信息: %s\n", sysInfo)

	// 示例3: 执行脚本文件
	filename := "D:\\workdata\\golang\\src\\testgo\\php\\bili\\start.ps1"
	if _, err := os.Stat(filename); err == nil {
		output, err := RunPowerShellFile(filename, "-Param1", "value1")
		if err != nil {
			log.Printf("脚本执行失败: %v", err)
		} else {
			fmt.Printf("脚本输出: %s\n", output)
		}
	}
}

func main() {
	router := gin.Default()
	router.GET("/post", func(c *gin.Context) {
		main2()
		c.JSON(200, gin.H{
			"html": "<b>Hello, world!</b>",
		})
	})
	router.Run(":8081")
}
