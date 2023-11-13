package main

import (
	"debug/elf"
	"fmt"
	"os"
	"testing"
)

func TestDiffElF(t *testing.T) {
	if len(os.Args) != 3 {
		fmt.Println("参数不对")
		os.Exit(0)
	}

	strFile1 := os.Args[1]
	strFile2 := os.Args[2]
	f1, e := elf.Open(strFile1)
	if e != nil {
		panic(e)
	}

	f2, e := elf.Open(strFile2)
	if e != nil {
		panic(e)
	}
	mapSection1 := make(map[string]string, 0)
	mapSection2 := make(map[string]string, 0)

	//[Nr]    Name    Type    Address    Offset    Size    EntSize    Flags    Link    Info    Align
	var size1 uint64
	var size2 uint64
	for _, s := range f1.Sections {
		mapSection1[s.Name] = fmt.Sprintf("%s\t%s\t%s\t%010x\t%010x\t%d\t%x\t%s\t%x\t%x\t%x\t", s.Name, strFile1, s.Type.String(), s.Addr, s.Offset, s.Size, s.Entsize, s.Flags.String(), s.Link, s.Info, s.Addralign)
		size1 += s.Size
	}

	for _, s := range f2.Sections {
		mapSection2[s.Name] = fmt.Sprintf("%s\t%s\t%s\t%010x\t%010x\t%d\t%x\t%s\t%x\t%x\t%x\t", s.Name, strFile2, s.Type.String(), s.Addr, s.Offset, s.Size, s.Entsize, s.Flags.String(), s.Link, s.Info, s.Addralign)
		size2 += s.Size
	}

	fmt.Printf("%s:%d\t%s:%d", strFile1, size1, strFile2, size2)

	fmt.Println("Name\tFile\tType\tAddress\tOffset\tSize\tEntSize\tFlags\tLink\tInfo\tAlign")
	for k, v := range mapSection1 {
		fmt.Println(v)
		if v1, found := mapSection2[k]; found {
			fmt.Println(v1)
			delete(mapSection2, k)
		}
	}

	for _, v := range mapSection2 {
		fmt.Println(v)
	}
}
