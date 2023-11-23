package algorithm

import (
	"fmt"
	"slices"
	"strconv"
	"strings"
	"time"
)

type Algorithm struct{}

/*
let backtracking=(路径，选择列表) =>{
    if (满足结束条件)) {
        存放路径;
        return;
    }
    for (选择：路径，选择列表) {
        做出选择；
        backtracking(路径，选择列表); // 递归
        回溯，撤销处理结果
    }
}
*/
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
			if slices.Index(path, nums[i]) > -1 {
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

/*
你要开发一座金矿，地质勘测学家已经探明了这座金矿中的资源分布，并用大小为 m * n 的网格

	进行了标注。每个单元格中的整数就表示这一单元格中的黄金数量；如果该单元格是空的，那么就是

。

为了使收益最大化，矿工需要按以下规则来开采黄金：

每当矿工进入一个单元，就会收集该单元格中的所有黄金。
矿工每次可以从当前位置向上下左右四个方向走。
每个单元格只能被开采（进入）一次。
不得开采（进入）黄金数目为

	的单元格。

矿工可以从网格中 「任意一个」 有黄金的单元格出发或者是停止。

输入：grid = [[0,6,0],[5,8,7],[0,9,0]]

输出：24

解释：
[[0,6,0],

	[5,8,7],
	[0,9,0]]

一种收集最多黄金的路线是：9 -> 8 -> 7。
*/
func (*Algorithm) GetMaximumGold(g [][]int) int {
	m := len(g)
	n := len(g[0])
	vis := make([][]bool, m)
	for i := range vis {
		vis[i] = make([]bool, n)
		for j := 0; j < n; j++ {
			vis[i][j] = false
		}
	}
	dirs := [][]int{
		{1, 0},
		{-1, 0},
		{0, 1},
		{0, -1},
	}

	for i := 0; i < m; i++ {
		for j := 0; j < n; j++ {
			vis[i][j] = false
		}
	}
	var dfs func(x int, y int) int
	layout := 0
	dfs = func(x int, y int) int {
		layout++
		ans := g[x][y]
		for _, d := range dirs {
			nx := x + d[0]
			ny := y + d[1]
			if nx < 0 || nx >= m || ny < 0 || ny >= n {
				continue
			}
			if g[nx][ny] == 0 {
				continue
			}
			if vis[nx][ny] {
				continue
			}
			vis[nx][ny] = true
			ans = max(ans, g[x][y]+dfs(nx, ny))
			vis[nx][ny] = false
		}
		return ans
	}
	ans := 0
	for i := 0; i < m; i++ {
		for j := 0; j < n; j++ {
			if g[i][j] != 0 {
				vis[i][j] = true
				ans = max(ans, dfs(i, j))
				vis[i][j] = false
			}
		}
	}
	return ans
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

// 给你一个整数数组 nums ，数组中的元素 互不相同 。返回该数组所有可能的子集（幂集）。
func (*Algorithm) CombinationSum(candidates []int, target int) [][]int {
	result := [][]int{}
	visited := []int{}
	var backTracing func(sum, cur int)
	backTracing = func(sum, cur int) {
		if target == sum {
			newList := make([]int, len(visited))
			copy(newList, visited)
			result = append(result, newList)
			fmt.Printf("target: %d, sum: %d, visited: %v\n", target, sum, visited)
			fmt.Println(strings.Repeat("=", 100))
		}
		if target <= sum {
			return
		}
		for i := cur; i < len(candidates); i++ {
			visited = append(visited, candidates[i])
			fmt.Printf("%d 进入, %v\n", candidates[i], visited)
			backTracing(sum+candidates[i], i)
			visited = visited[:len(visited)-1]
			fmt.Printf("%d 退出, %v\n", candidates[i], visited)
		}
	}
	backTracing(0, 0)
	return result
}

// 找出所有相加之和为 n 的 k 个数的组合。组合中只允许含有 1 - 9 的正整数，并且每种组合中不存在重复的数字。
func (*Algorithm) CombinationSum3(n, k int) [][]int {
	ans := [][]int{}
	var backTracing func(start int, path []int)
	backTracing = func(start int, path []int) {
		if len(path) == k {
			sum := 0
			for i := 0; i < len(path); i++ {
				sum += path[i]
			}
			if sum == n {
				newPath := make([]int, len(path))
				copy(newPath, path)
				ans = append(ans, newPath)
				fmt.Printf("sum: %d, path: %v, 完成\n", sum, path)
				fmt.Println(strings.Repeat("=", 100))
				return
			}
		}
		for i := start; i <= 9; i++ {
			path = append(path, i)
			fmt.Printf("%d 加入, %v\n", i, path)
			backTracing(i+1, path)
			path = path[:len(path)-1]
			fmt.Printf("%d 删除, %v\n", i, path)
		}
	}
	backTracing(1, []int{})
	return ans
}

// 给定一个仅包含数字 2-9 的字符串，返回所有它能表示的字母组合。答案可以按 任意顺序 返回。
func (*Algorithm) LetterCombinations(digits string) []string {
	if len(digits) == 0 {
		return []string{}
	}
	dic := map[int]string{
		2: "abc",
		3: "def",
		4: "ghi",
		5: "gkl",
		6: "mno",
		7: "pqrs",
		8: "tuv",
		9: "wxyz",
	}
	ans := []string{}
	var backTracing func(cur string, index int)
	backTracing = func(cur string, index int) {
		if index > len(digits)-1 {
			ans = append(ans, cur)
			fmt.Printf("合法路径: %s\n", cur)
			return
		}
		i, _ := strconv.Atoi(string(rune(digits[index])))
		curDic := dic[i]
		for i := 0; i < len(curDic); i++ {
			backTracing(cur+string(curDic[i]), index+1)
		}
	}
	backTracing("", 0)
	return ans
}

// 三步问题。有个小孩正在上楼梯，楼梯有n阶台阶，小孩一次可以上1阶、2阶或3阶。实现一种方法，计算小孩有多少种上楼梯的方式。结果可能很大，你需要对结果模1000000007。
func (*Algorithm) WaysToStep(n int) int {
	var ans int
	m := []int{1, 2, 3}
	var backTracing func(path []int, sum int)
	backTracing = func(path []int, sum int) {
		if sum >= n {
			if sum == n {
				ans++
				fmt.Printf("%v\n", path)
			}
			return
		}
		for i := 0; i < 3; i++ {
			path = append(path, m[i])
			backTracing(path, sum+m[i])
			path = path[:len(path)-1]
		}
	}
	backTracing([]int{}, 0)
	return ans
}

func (*Algorithm) WaysToStep2(n int) int {
	dp := map[int]int{
		0: 0,
		1: 1,
		2: 2,
		3: 4,
	}
	mod := 1000000007
	for i := 4; i <= n; i++ {
		dp[i] = (dp[i-1] + dp[i-2] + dp[i-3]) % mod
	}
	return dp[n]
}

// 给定一个数组 candidates 和一个目标数 target ，找出 candidates 中所有可以使数字和为 target 的组合。
func (*Algorithm) CombinationSum2(candidates []int, target int) [][]int {
	slices.Sort(candidates)
	fmt.Printf("%v\n", candidates)
	ans := [][]int{}
	var backTracing func(start int, path []int, sum int)
	backTracing = func(start int, path []int, sum int) {
		fmt.Printf("%v, %p\n", path, path)
		if sum >= target {
			if sum == target {
				fmt.Printf("sum: %d, target: %d, path: %v\n", sum, target, path)
				newPath := make([]int, len(path))
				copy(newPath, path)
				ans = append(ans, newPath)
				return
			}
		}
		for i := start; i < len(candidates); i++ {
			if i-1 >= start && candidates[i-1] == candidates[i] {
				continue
			}
			path = append(path, candidates[i])
			backTracing(start+1, path, sum+candidates[i])
			path = path[:len(path)-1]
		}
	}
	backTracing(0, []int{}, 0)
	return ans
}

// 给定一个可包含重复数字的序列 nums ，按任意顺序 返回所有不重复的全排列。
func (*Algorithm) PermuteUnique(nums []int) [][]int {
	ans := [][]int{}
	used := []bool{}
	for i := 0; i < len(nums); i++ {
		used = append(used, false)
	}
	var backTracing func(start int, path []int)
	backTracing = func(start int, path []int) {
		if start == len(nums) {
			ans = append(ans, path)
			return
		}
		for i := 0; i < len(nums); i++ {
			if used[i] || (i > 0 && nums[i] == nums[i-1] && !used[i-1]) {
				continue
			}
			path = append(path, nums[i])
			used[i] = true
			backTracing(start+1, path)
			used[i] = false
			path = path[:len(path)-1]
		}
	}
	slices.Sort(nums)
	backTracing(0, []int{})
	return ans
}
