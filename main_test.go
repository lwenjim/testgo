package main

import (
	"fmt"
	"testing"
)

// https://leetcode.cn/problems/container-with-most-water/description/?envType=study-plan-v2&envId=top-100-liked
func TestMaxArea(t *testing.T) {
	var maxArea = func(height []int) (ans int) {
		left, right := 0, len(height)-1
		for left < right {
			area := (right - left) * min(height[left], height[right])
			ans = max(ans, area)
			if height[left] < height[right] {
				// height[left]  与右边的任意垂线都无法组成一个比 ans 更大的面积
				left++
			} else {
				// height[right] 与左边的任意垂线都无法组成一个比 ans 更大的面积
				right--
			}
		}
		return
	}
	var nums = []int{1, 8, 6, 2, 5, 4, 8, 3, 7}
	var result = maxArea(nums)
	fmt.Printf("result: %v\n", result)
}

// https://leetcode.cn/problems/move-zeroes/description/?envType=study-plan-v2&envId=top-100-liked
func TestMoveZeroes(t *testing.T) {
	var moveZeroes = func(nums []int) {
		left, right, n := 0, 0, len(nums)
		for right < n {
			if nums[right] != 0 {
				nums[left], nums[right] = nums[right], nums[left]
				left++
			}
			right++
		}
	}
	var nums = []int{0, 1, 0, 3, 12}
	moveZeroes(nums)
	fmt.Printf("nums: %v\n", nums)
}

// https://leetcode.cn/problems/longest-consecutive-sequence/description/?envType=study-plan-v2&envId=top-100-liked
func TestLongestConsecutive(t *testing.T) {
	var longestConsecutive = func(nums []int) int {
		numSet := map[int]bool{}
		for _, num := range nums {
			numSet[num] = true
		}
		longestStreak := 0
		for num := range numSet {
			if !numSet[num-1] {
				currentNum := num
				currentStreak := 1
				for numSet[currentNum+1] {
					currentNum++
					currentStreak++
				}
				if longestStreak < currentStreak {
					longestStreak = currentStreak
				}
			}
		}
		return longestStreak
	}
	var nums = []int{100, 4, 200, 1, 3, 2}
	var result = longestConsecutive(nums)
	fmt.Printf("result: %v\n", result)
}

// https://leetcode.cn/problems/group-anagrams/?envType=study-plan-v2&envId=top-100-liked
func TestGroupAnagrams(t *testing.T) {
	var groupAnagrams = func(strs []string) [][]string {
		mp := map[[26]int][]string{}
		for _, str := range strs {
			cnt := [26]int{}
			for _, b := range str {
				cnt[b-'a']++
			}
			mp[cnt] = append(mp[cnt], str)
		}
		ans := make([][]string, 0, len(mp))
		for _, v := range mp {
			ans = append(ans, v)
		}
		return ans
	}
	strs := []string{"eat", "tea", "tan", "ate", "nat", "bat"}
	arr := groupAnagrams(strs)
	fmt.Printf("arr: %v\n", arr)
}
