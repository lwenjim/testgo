package main

import (
	"fmt"
	"testing"

	"github.com/xuri/excelize/v2"
)

func TestMain(t *testing.T) {
	f, err := excelize.OpenFile("E:\\ExcelDemo\\titanic.xlsx")
	if err != nil {
		fmt.Println(err)
		return
	}
	defer func() {
		if err := f.Close(); err != nil {
			fmt.Println(err)
		}
	}()
	_, err = f.GetRows("titanic")
	if err != nil {
		fmt.Println(err)
		return
	}
}
