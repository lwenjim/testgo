package main

import (
	"fmt"
	"os"
	"path/filepath"

	"gopkg.in/yaml.v2"
)

type Config struct {
	ApiVersion string `yaml:"apiVersion"`
	Data       string `yaml:"data"`
}

func main() {
	files, err := filepath.Glob("*.yaml")
	if err != nil {
		fmt.Printf("err: %v\n", err)
		return
	}

	for _, file := range files {
		buf, err := os.ReadFile(file)
		if err != nil {
			fmt.Printf("err: %v\n", err)
			return
		}
		var data []Config
		err = yaml.Unmarshal(buf, data)
		if err != nil {
			fmt.Printf("err: %v\n", err)
			return
		}
		fmt.Printf("data: %v\n", &data)
		for _, item := range data {
			fmt.Printf("item.Data: %v\n", item.Data)
			return
		}
	}
}
