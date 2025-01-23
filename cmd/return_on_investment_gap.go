package cmd

import (
	"fmt"
	"os"
	"regexp"

	"github.com/apaxa-go/eval"
	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use:   "g",
	Short: "tool kit",
	Long:  "tool kit for study",
}
var subroot = &cobra.Command{
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

func formatCommas(num int) string {
	str := fmt.Sprintf("%d", num)
	re := regexp.MustCompile("(\\d+)(\\d{3})")
	for n := ""; n != str; {
		n = str
		str = re.ReplaceAllString(str, "$1,$2")
	}
	return str
}
func init() {
	rootCmd.AddCommand(subroot)
}

func Execute() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}
