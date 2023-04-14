package main

import (
	"testing"
	"time"
)

type IName interface {
	Do(string) string
}

type Subject struct {
	Name IName
}

type MName func(string) string

func (r MName) Do(s string) string {
	return s
}

func TestName(t *testing.T) {
	func1 := func(s string) string {
		return s
	}
	mName1 := MName(func1)
	func2 := func(s string) string {
		mName1.Do(s)
		return s + ":" + time.Now().String()
	}
	mName2 := MName(func2)
	s := Subject{
		Name: mName2,
	}
	println(s.Name.Do("123"))
}
