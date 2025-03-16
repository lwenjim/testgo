package examples

import (
	"fmt"
	"testing"
)

func TestAlgorithm_GenerateParenthesis(t *testing.T) {
	a := new(Algorithm)
	res := a.GenerateParenthesis(2)
	for v := range res {
		fmt.Printf("res: %v\n", res[v])
	}
}

func TestAlgorithm_Permute(t *testing.T) {
	a := new(Algorithm)
	res := a.PermuteUnique([]int{3, 2, 1, 4})
	fmt.Printf("res: %v\n", res)
}

func TestAlgorithm_TotalNQueens(t *testing.T) {
	a := new(Algorithm)
	res := a.TotalNQueens(6)
	fmt.Printf("res: %v\n", res)
}

func TestAlgorithm_Subsets(t *testing.T) {
	a := new(Algorithm)
	arr := []int{1, 4, 8, 2}
	res := a.Subsets(arr)
	fmt.Printf("res: %v\n", res)
}

func TestAlgorithm_Combine(t *testing.T) {
	// fun1 := func(sli []int) {
	// 	fmt.Printf("%p\n", sli)
	// }
	// sli := make([]int, 0)
	// fun1(sli)
	// fmt.Printf("%p\n", sli)

	// fun1 := func(mp map[int]int) {
	// 	fmt.Printf("%p\n", mp)
	// }
	// mp := make(map[int]int, 0)
	// fun1(mp)
	// fmt.Printf("%p\n", mp)

	// fun1 := func(ch chan int) {
	// 	fmt.Printf("%p\n", ch)
	// }
	// ch := make(chan int)
	// fun1(ch)
	// fmt.Printf("%p\n", ch)

	// type P struct {
	// 	id int
	// }
	// fun1 := func(p P) {
	// 	fmt.Printf("%p\n", &p)
	// }
	// p := P{0}
	// fun1(p)
	// fmt.Printf("%p\n", &p)

	// fun2 := func(num int) {
	// 	fmt.Printf("%p\n", &num)
	// }
	// num := 2
	// fun2(num)
	// fmt.Printf("%p\n", &num)

	// fun2 := func(str string) {
	// 	fmt.Printf("%p\n", &str)
	// }
	// str := "abc"
	// fun2(str)
	// fmt.Printf("%p\n", &str)

	// fun2 := func(byts []byte) {
	// 	fmt.Printf("%p\n", &byts)
	// }
	// byts := []byte("abc")
	// fun2(byts)
	// fmt.Printf("%p\n", &byts)

	// var sli []int
	// sli = append(sli, 1)
	// fmt.Printf("%p\n", sli)
	// sli2 := make([]int, 1)
	// copy(sli2, sli)
	// fmt.Printf("%p\n", sli2)

	a := new(Algorithm)
	res := a.Combine(10, 5)
	fmt.Printf("res: %v\n", res)

}

func TestAlgorithm_CombinationSum(t *testing.T) {
	a := new(Algorithm)
	arr := []int{1, 4, 8, 2}
	res := a.CombinationSum(arr, 6)
	fmt.Printf("res: %v\n", res)
}
func TestAlgorithm_CombinationSum3(t *testing.T) {
	a := new(Algorithm)
	res := a.CombinationSum3(9, 3)
	fmt.Printf("res: %v\n", res)
}
func TestAlgorithm_LetterCombinations(t *testing.T) {
	a := new(Algorithm)
	res := a.LetterCombinations("23")
	fmt.Printf("res: %v\n", res)
}
func TestAlgorithm_LWaysToSteps(t *testing.T) {
	a := new(Algorithm)
	res := a.WaysToStep2(10)
	fmt.Printf("res: %v\n", res)
}
func TestAlgorithm_CombinationSum2(t *testing.T) {
	a := new(Algorithm)
	res := a.CombinationSum2([]int{2, 5, 2, 1, 2}, 8)
	fmt.Printf("res: %v\n", res)
}
func TestAlgorithm_PermuteUnique(t *testing.T) {
	a := new(Algorithm)
	res := a.PermuteUnique([]int{2, 5, 2, 1, 2})
	fmt.Printf("res: %v\n", res)
}
func TestAlgorithm_GetMaximumGold(t *testing.T) {
	a := new(Algorithm)
	res := a.GetMaximumGold([][]int{{0, 6, 0}, {5, 8, 7}, {0, 9, 0}})
	fmt.Printf("res: %v\n", res)
}
