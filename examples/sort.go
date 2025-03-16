package examples

func BubbleSort(s []int) {
	for i := 0; i < len(s); i++ {
		for j := i + 1; j < len(s); j++ {
			if s[i] > s[j] {
				s[i], s[j] = s[j], s[i]
			}
		}
	}
}

func SelectionSort(s []int) {
	for i := 0; i < len(s); i++ {
		m := s[i]
		g := i
		for j := i + 1; j < len(s); j++ {
			if m > s[j] {
				m = s[j]
				g = j
			}
		}
		s[i], s[g] = s[g], s[i]
	}
}

func QuickSort(arr []int) []int {
	return quickSort(arr, 0, len(arr)-1)
}

func quickSort(arr []int, left, right int) []int {
	if left < right {
		partitionIndex := partition(arr, left, right)
		quickSort(arr, left, partitionIndex-1)
		quickSort(arr, partitionIndex+1, right)
	}
	return arr
}

func partition(arr []int, left, right int) int {
	pivot := left
	j := pivot + 1

	for i := j; i <= right; i++ {
		if arr[i] < arr[pivot] {
			arr[i], arr[j] = arr[j], arr[i]
			j += 1
		}
	}
	arr[pivot], arr[j-1] = arr[j-1], arr[pivot]
	return j - 1
}

func InsertionSort(s []int) {
	for i := 1; i < len(s); i++ {
		for j := i - 1; j >= 0; j-- {
			if s[j] > s[i] {
				s[j], s[i] = s[i], s[j]
				break
			}
		}
	}
}

func MergeSort(arr []int) []int {
	if len(arr) < 2 {
		return arr
	}
	m := len(arr) / 2
	l := arr[0:m]
	r := arr[m:]
	return merge(MergeSort(l), MergeSort(r))
}

func merge(l []int, r []int) []int {
	var result []int
	for len(l) != 0 && len(r) != 0 {
		if l[0] < r[0] {
			result = append(result, l[0])
			l = l[1:]
		} else {
			result = append(result, r[0])
			r = r[1:]
		}
	}
	for len(l) != 0 {
		result = append(result, l[0])
		l = l[1:]
	}
	for len(r) != 0 {
		result = append(result, r[0])
		r = r[1:]
	}
	return result
}

func HeapSort(arr []int) []int {
	arrLen := len(arr)
	buildMaxHeap(arr, arrLen)
	for i := arrLen - 1; i >= 0; i-- {
		arr[i], arr[0] = arr[0], arr[i]
		arrLen -= 1
		heapify(arr, 0, arrLen)
	}
	return arr
}

func buildMaxHeap(arr []int, arrLen int) {
	for i := arrLen / 2; i >= 0; i-- {
		heapify(arr, i, arrLen)
	}
}

func heapify(arr []int, i, arrLen int) {
	left := 2*i + 1
	right := 2*i + 2
	j := i
	if left < arrLen && arr[left] > arr[j] {
		j = left
	}
	if right < arrLen && arr[right] > arr[j] {
		j = right
	}
	if j != i {
		arr[i], arr[j] = arr[j], arr[i]
		heapify(arr, j, arrLen)
	}
}
