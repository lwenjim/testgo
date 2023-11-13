package main

import (
	"debug/elf"
	"debug/gosym"
	"fmt"
	"os"
	"testing"
)

func TestExpElf(t *testing.T) {
	if len(os.Args) != 2 {
		fmt.Println("参数不对")
		os.Exit(0)
	}

	strFile1 := os.Args[1]

	f1, err := elf.Open(strFile1)
	if err != nil {
		panic(err)
	}

	symtab, err := f1.Section(".gosymtab").Data()
	if err != nil {
		f1.Close()
		panic(".gosymtab 异常")
	}

	gopclntab, err := f1.Section(".gopclntab").Data()
	if err != nil {
		f1.Close()
		panic(".gopclntab 异常")
	}

	pcln := gosym.NewLineTable(gopclntab, f1.Section(".text").Addr)
	var tab *gosym.Table
	tab, err = gosym.NewTable(symtab, pcln)
	if err != nil {
		f1.Close()
		panic(err)
	}
	for _, x := range tab.Funcs {
		fmt.Printf("addr:0x%x\t\tname:%s,\t", x.Entry, x.Name)
	}
}
