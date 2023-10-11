package b

import (
	"fmt"

	_ "github.com/lwenjim/testgo/a"
)

func init() {
	fmt.Println("bbb")
}

func Say() {}
