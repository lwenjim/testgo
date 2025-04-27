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

func init() {
	rootCmd.AddCommand(redis.RedisCmd)
}

func Exec() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}
