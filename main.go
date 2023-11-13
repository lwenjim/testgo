package main

import (
	"encoding/json"
	"fmt"
	"os"
	"runtime/pprof"

	_ "net/http/pprof"
)

func main() {
	f, _ := os.OpenFile("cpu.pprof", os.O_CREATE|os.O_RDWR, 0644)
	defer f.Close()
	_ = pprof.StartCPUProfile(f)
	defer pprof.StopCPUProfile()

	tmp, _ := os.ReadFile("a.log")
	var words []string
	_ = json.Unmarshal(tmp, &words)

	ant := maxProduct(words)

	fmt.Printf("ant: %v\n", ant)
}

func maxProduct(words []string) int {
	boxLen := len(words)
	ans := 0
	m := make(map[string]int)
	for i := 0; i < boxLen; i++ {
		l := 0
		for j := 0; j < len(words[i]); j++ {
			l |= 1 << (words[i][j] - 'a')
		}
		m[words[i]] = l
	}
	for i := 0; i < boxLen; i++ {
		for j := i + 1; j < boxLen; j++ {
			if m[words[i]]&m[words[j]] == 0 {
				ans = max(ans, len(words[i])*len(words[j]))
			}
		}
	}
	return ans
}

// func maxProduct(words []string) int {
// 	x := 0
// 	y := 0
// 	boxLen := len(words)
// 	for i := 0; i < boxLen-1; i++ {
// 		m := make(map[byte]int)
// 		for j := 0; j < len(words[i]); j++ {
// 			if len(m) >= 26 {
// 				break
// 			}
// 			if _, ok := m[words[i][j]]; ok {
// 				continue
// 			}
// 			m[words[i][j]] = 1
// 		}
// 		for j := i + 1; j < boxLen; j++ {
// 			if i == j {
// 				continue
// 			}
// 			if x == i && y == j {
// 				continue
// 			}

// 			isExists := false
// 			n := make(map[byte]int)
// 			for z := 0; z < len(words[j]); z++ {
// 				if len(n) >= 26 {
// 					break
// 				}
// 				if _, ok := m[words[j][z]]; ok {
// 					isExists = true
// 					break
// 				}
// 				n[words[j][z]] = 1
// 			}

// 			if isExists {
// 				continue
// 			}
// 			if x == 0 && y == 0 {
// 				x = i
// 				y = j
// 			}
// 			if len(words[i])*len(words[j]) <= len(words[x])*len(words[y]) {
// 				continue
// 			}
// 			x = i
// 			y = j
// 		}
// 	}
// 	fmt.Printf("x: %d\n", x)
// 	fmt.Printf("y: %d\n", y)
// 	fmt.Printf("max: %d, len: %d\n", len(words[x])*len(words[y]), len(words))
// 	if x == y {
// 		return 0
// 	}
// 	return len(words[x]) * len(words[y])
// }
