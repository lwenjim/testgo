package cmd

import (
	"fmt"
	"strings"

	"github.com/spf13/cobra"
	"github.com/traefik/yaegi/interp"
	"github.com/traefik/yaegi/stdlib"
)

var subCmd = &cobra.Command{
	Use:   "sub",
	Short: "eval expr string",
	Long:  "eval expr from input or args",
	Run: func(cmd *cobra.Command, args []string) {
		exprStr, err := getParams(args)
		if err != nil {
			fmt.Println(err.Error())
			return
		}
		if len(exprStr) == 0 {
			fmt.Println("len(exprStr) == 0")
			return
		}
		i := interp.New(interp.Options{})
		_ = i.Use(stdlib.Symbols)
		for _, v := range strings.Split(exprStr, ";") {
			val, err := i.Eval(v)
			if err != nil {
				fmt.Println(err.Error())
				continue
			}
			fmt.Printf("%s = %d\n", v, val.Interface().(int))
		}
	},
}

func init() {
	rootCmd.AddCommand(subCmd)
}
