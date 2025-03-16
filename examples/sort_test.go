package examples

import (
	"fmt"
	"testing"
)

func TestSort(t *testing.T) {
	s := []int{1, 2, 4, 3, 8, 7, 5}
	InsertionSort(s)
	fmt.Printf("s: %v\n", s)
}
