package examples

import (
	"encoding/json"
	"fmt"
	"net/url"
	"os"
	"testing"
)

func TestJsonConvert(t *testing.T) {
	var bodyJson [4096]byte
	total, err := os.Stdin.Read(bodyJson[:])
	if err != nil {
		fmt.Println(err)
		return
	} else if total == 0 {
		fmt.Println("empty")
		return
	}

	var params map[string]interface{}
	if err := json.Unmarshal(bodyJson[:total], &params); err != nil {
		fmt.Println(err)
		return
	}
	switch os.Args[1] {
	case "application/x-www-form-urlencoded":
		flieds := url.Values{}
		for k, v := range params {
			flieds.Add(k, fmt.Sprintf("%v", v))
		}
		fmt.Println(flieds.Encode())
	case "multipart/form-data":
		for k, v := range params {
			fmt.Printf("--%s\nContent-Disposition: form-data; name=\"%s\"\nContent-Type: text/plain\n\n%v\n", os.Args[2], k, v)
		}
		fmt.Printf("--%s--", os.Args[2])
	case "application/json":
		buff, _ := json.Marshal(params)
		fmt.Printf("%s", string(buff))
	}
}
