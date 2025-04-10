package mongodb

import (
	"fmt"

	"github.com/spf13/cobra"
)

var MongodbCmd = &cobra.Command{
	Use: "mongodb",
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Println("abc")
	},
}
