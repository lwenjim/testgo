package cmd 

import (
	"fmt"

	"github.com/apaxa-go/eval"
	"github.com/spf13/cobra"
)

var exprCmd = &cobra.Command{
	Use:   "expr",
	Short: "eval expr string",
	Long:  "eval expr from input or args",
	Run: func(cmd *cobra.Command, args []string) {
		var exprStr string
		if len(args) == 1 {
			exprStr = args[0]
		}

		if len(exprStr) == 0 {
			if i, err := fmt.Scan(&exprStr); err != nil {
				fmt.Println(err.Error())
				return
			} else if i <= 0 {
				fmt.Println(err.Error())
				return
			}
		}

		if len(exprStr) == 0 {
			fmt.Println("error param")
		}
		expr, err := eval.ParseString(exprStr, "")
		if err != nil {
			fmt.Println(err.Error())
			return
		}
		r, err := expr.EvalToInterface(nil)
		if err != nil {
			fmt.Println(err.Error())
			return
		}
		fmt.Println(r)
	},
}

func init() {
	rootCmd.AddCommand(exprCmd)
}
