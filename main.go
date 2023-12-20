package main

type Node3 interface {
	Add(a, b int32) int32
	Sub(a, b int64) int64
}

type SObj struct{ id int32 }

func (adder SObj) Add(a, b int32) int32 { return a + b }
func (adder SObj) Sub(a, b int64) int64 { return a - b }

func main() {
	m := Node3(SObj{id: 6754})
	m.Add(10, 32)
}
