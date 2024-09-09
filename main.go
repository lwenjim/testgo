package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"gopkg.in/yaml.v2"
)

type Config struct {
	ApiVersion string `yaml:"apiVersion"`
	Data       string `yaml:"data"`
}

func main() {
	files, err := filepath.Glob("/Users/jim/Workdata/goland/src/jspp/k8sconfig-dev/*.yaml")
	if err != nil {
		fmt.Printf("err: %v\n", err)
		return
	}

	for _, file := range files {
		fmt.Printf("file: %v\n", file)
		buf, err := os.ReadFile("/Users/jim/Workdata/goland/src/jspp/k8sconfig-dev/usersv.yaml")
		if err != nil {
			fmt.Printf("err: %v\n", err)
			return
		}
		yamls := string(buf)
		strs := strings.Split(yamls, "---")
		var data Config
		err = yaml.Unmarshal([]byte(strs[0]), &data)
		if err != nil {
			fmt.Printf("err: %v\n", err)
			return
		}
		fmt.Printf("data: %v\n", data)
		break
	}
}
