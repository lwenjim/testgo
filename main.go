package main

import (
	"bytes"
	"fmt"

	"github.com/ledongthuc/pdf"
)

func main() {
	//    runtime.GOMAXPROCS(0)
	//    f, _ := os.Create("trace.output")
	//    defer f.Close()
	//    _ = trace.Start(f)
	//    defer trace.Stop()
	//    var wg sync.WaitGroup
	//    for i := 0; i < 30; i++ {
	//        wg.Add(1)
	//        go func() {
	//            defer wg.Done()
	//            t := 0
	//            for i:=0;i<1e8;i++ {
	//                t+=2
	//            }
	//            fmt.Println("total:", t)
	//        }()
	//    }
	//    wg.Wait()

	pdf.DebugOn = true
	content, err := readPdf("/Users/jim/Downloads/BILL-DETAIL.pdf") // Read local pdf file
	if err != nil {
		panic(err)
	}
	fmt.Println(content)
}

func readPdf(path string) (string, error) {
	f, r, err := pdf.Open(path)
	defer f.Close()
	if err != nil {
		return "", err
	}
	var buf bytes.Buffer
	b, err := r.GetPlainText()
	if err != nil {
		return "", err
	}
	buf.ReadFrom(b)
	return buf.String(), nil
}
