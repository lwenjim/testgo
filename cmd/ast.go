package cmd

import (
	"go/parser"
	"go/token"
	"log"

	"github.com/spf13/cobra"
)

var astCmd = &cobra.Command{
	Use:   "ast",
	Short: "get text length",
	Long:  "get text length for string",
	Run: func(cmd *cobra.Command, args []string) {
		fset := token.NewFileSet()

		f, err := parser.ParseFile(fset, "main.go", nil, parser.ParseComments)
		if err != nil {
			log.Fatal(err)
		}

		for _, comment := range f.Comments {
			log.Printf("Comment: %s", comment.Text())
		}
	},
}

func init() {
	rootCmd.AddCommand(astCmd)
}
