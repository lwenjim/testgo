package main

import (
	"fmt"
	"math/big"
	"time"
)

func main() {
	allInputs := [5]int{10000, 50000, 100000, 500000, 1000000}
	for i := 0; i < len(allInputs); i++ {
		var before = GetTimeStamp()
		var factorial *big.Int = big.NewInt(1)
		for j := 1; j <= allInputs[i]; j++ {
			factorial = factorial.Mul(factorial, big.NewInt(int64(j)))
		}
		var after = GetTimeStamp()
		var elapsedTime = after - before
		fmt.Printf("Elapsed Time for %d is %d\n", allInputs[i], elapsedTime)
	}
}

func GetTimeStamp() int64 {
	return time.Now().UnixNano() / int64(time.Millisecond)
}
