package cmd

import (
	"fmt"
	"jspp/testgo/docker/redis"
	"os"

	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use:   "testgo",
	Short: "tool kit",
	Long:  "tool kit for study",
}

func getParams(args []string) (string, error) {
	var exprStr string
	if len(args) == 1 {
		exprStr = args[0]
	}

	if len(exprStr) == 0 {
		if _, err := fmt.Scan(&exprStr); err != nil {
			fmt.Println(err.Error())
			return "", err
		}
	}
	return exprStr, nil
}
func init() {
	rootCmd.AddCommand(redis.RedisCmd)
}
func Exec() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}
