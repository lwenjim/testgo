package algorithm

import (
	"fmt"
	"slices"
	"strings"
	"time"
)

type Algorithm struct{}

// 数字 n 代表生成括号的对数，请你设计一个函数，用于能够生成所有可能的并且 有效的 括号组合。
func (*Algorithm) GenerateParenthesis(n int) []string {
	res := make([]string, 0)
	var backTracing func(lRemain, rRemain int, str string, layout int)
	backTracing = func(lRemain, rRemain int, str string, layout int) {
		layout++
		if 2*n == len(str) {
			res = append(res, str)
			fmt.Printf("第%d层, 合法路径, str: %s\n", layout, str)
			fmt.Println(strings.Repeat("=", 100))
			return
		}
		if lRemain > 0 {
			fmt.Printf("第%d层, 左边插入, str: %s\n", layout, str+"(")
			backTracing(lRemain-1, rRemain, str+"(", layout)
		}
		if lRemain < rRemain {
			fmt.Printf("第%d层, 右边插入, str: %s\n", layout, str+")")
			backTracing(lRemain, rRemain-1, str+")", layout)
		}
	}
	backTracing(n, n, "", 0)
	return res
}

// 给定一个不含重复数字的数组 nums ，返回其 所有可能的全排列 。你可以 按任意顺序 返回答案。
func (*Algorithm) Permute(nums []int) [][]int {
	startTime := time.Now()
	if len(nums) <= 0 {
		return [][]int{}
	}
	res := make([][]int, 0)
	var backTrack func(path []int, layout int)
	backTrack = func(path []int, layout int) {
		layout++
		if len(path) == len(nums) {
			res = append(res, path)
			fmt.Printf("第%d层循环, 合法路径,  %v\n", layout, path)
			fmt.Println(strings.Repeat("=", 100))
			return
		}
		for i := 0; i < len(nums); i++ {
			if slices.Index[[]int, int](path, nums[i]) > -1 {
				fmt.Printf("第%d层循环, %d已存在, %v\n", layout, nums[i], path)
				continue
			}
			backTrack(append(path, nums[i]), layout)
			fmt.Printf("第%d层循环, %d加入, %v\n", layout, nums[i], path)
		}
		fmt.Printf("第%d层循环, 结束, %v\n", layout, path)
	}
	backTrack([]int{}, 0)
	fmt.Printf("take time: %fs\n", time.Since(startTime).Seconds())
	return res
}

// 研究的是如何将 n 个皇后放置在 n × n 的棋盘上，并且使皇后彼此之间不能相互攻击。
func (*Algorithm) TotalNQueens(n int) int {
	count := 0
	board := [][]string{}
	show := func() {
		for i := 0; i < n; i++ {
			for j := 0; j < n; j++ {
				fmt.Printf("%s\t", board[i][j])
			}
			fmt.Println("")
		}
		fmt.Printf("\n%s\n", strings.Repeat("=", 100))
	}
	isValid := func(row, col int, board [][]string, n int) bool {
		//所在行不用判断，每次都会下移一行
		//判断同一列的数据是否包含
		for i := 0; i < row; i++ {
			if board[i][col] == "*" {
				return false
			}
		}
		//判断45度对角线是否包含
		for i, j := row-1, col+1; i >= 0 && j < i; i, j = i-1, j+1 {
			if board[i][j] == "*" {
				return false
			}
		}
		//判断135度对角线是否包含
		for i, j := row-1, col-1; i >= 0 && j >= 0; i, j = i-1, j-1 {
			if board[i][j] == "*" {
				return false
			}
		}
		return true
	}
	var backTracing func(row int, board [][]string)
	backTracing = func(row int, board [][]string) {
		//走到最后一行，统计次数
		if row == n {
			count++
			fmt.Println("合法路线")
			show()
			return
		}
		for i := 0; i < n; i++ {
			//判断该位置是否可以放置
			if isValid(row, i, board, n) {
				//放置
				board[row][i] = "*"
				fmt.Printf("插入 row: %d, col: %d\n", row, i)
				show()
				//递归
				backTracing(row+1, board)
				//回溯，撤销处理结果
				board[row][i] = "."
				fmt.Printf("撤销 row: %d, col: %d\n", row, i)
				show()
			}
		}
	}
	for i := 0; i < n; i++ {
		t := make([]string, 0)
		for j := 0; j < n; j++ {
			t = append(t, ".")
		}
		board = append(board, t)
	}
	backTracing(0, board)
	return count
}

// 给你一个整数数组 nums ，数组中的元素 互不相同 。返回该数组所有可能的子集（幂集）。
func (*Algorithm) Subsets(arr []int) [][]int {
	res := make([][]int, 0)
	var backTracing func(index int, list []int)
	backTracing = func(index int, list []int) {
		newList := make([]int, len(list))
		copy(newList, list)
		res = append(res, newList)
		fmt.Printf("%v\n\n", list)
		for i := index; i < len(arr); i++ {
			list = append(list, arr[i])
			fmt.Printf("%d 进入, %v\n", arr[i], list)
			backTracing(i+1, list)
			list = list[:len(list)-1]
			fmt.Printf("%d 退出, %v\n", arr[i], list)
		}
	}
	backTracing(0, []int{})
	return res
}

// 给定两个整数 n 和 k，返回范围 [1, n] 中所有可能的 k 个数的组合。
func (*Algorithm) Combine(n, k int) [][]int {
	result := make([][]int, 0)
	index := 0
	var backTracing func(start int, path []int)
	backTracing = func(start int, path []int) {
		index++
		if len(path) == k {
			fmt.Printf("%d -> 符合条件\n\n", index)
			path2 := make([]int, len(path))
			copy(path2, path)
			result = append(result, path2)
			return
		}
		for i := start; i <= n; i++ {
			path = append(path, i)
			fmt.Printf("%d -> %d 进入, path: %v \n", index, i, path)
			backTracing(i+1, path)
			path = path[:len(path)-1]
			fmt.Printf("%d -> %d 退出, path: %v \n", index, i, path)
		}
	}
	backTracing(1, make([]int, 0))
	return result
}
