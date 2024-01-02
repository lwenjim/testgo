package main

type TypicalErr2 struct {
	e string
}

func (t TypicalErr2) Error() string {
	return t.e
}

func main() {
	err := "123"
	if e, ok := interface{}(err).(TypicalErr2); ok {
		println(e.Error())
	}
}
