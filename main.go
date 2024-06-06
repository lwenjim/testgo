package main

import (
	"fmt"
	"math/rand"
	"time"
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

	a := rand.Int63n(time.Now().Unix() - 7*24*3600)
	fmt.Println(time.Unix(a, 0).Format("2006-01-02 15:04:05.000"))
}
