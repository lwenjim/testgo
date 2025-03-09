package cmd

import (
	"fmt"

	"github.com/spf13/cobra"
)

var lenCmd = &cobra.Command{
	Use:   "len",
	Short: "get text length",
	Long:  "get text length for string",
	Run: func(cmd *cobra.Command, args []string) {
		var str string
		if len(args) == 1 {
			str = args[0]
		}
		if len(str) == 0 {
			if i, err := fmt.Scan(&str); err != nil {
				fmt.Println(err.Error())
				return
			} else if i <= 0 {
				fmt.Println(err.Error())
				return
			}
		}
		if len(str) == 0 {
			fmt.Println("error param")
		}
		fmt.Println(len(str))
	},
}

func init() {
	rootCmd.AddCommand(lenCmd)
}
