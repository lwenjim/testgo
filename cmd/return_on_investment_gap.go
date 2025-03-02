package cmd

import (
	"crypto/des"
	"fmt"
	"os"
	"strings"

	"github.com/apaxa-go/eval"
	"github.com/spf13/cobra"
	"github.com/traefik/yaegi/interp"
	"github.com/traefik/yaegi/stdlib"
)

var rootCmd = &cobra.Command{
	Use:   "g",
	Short: "tool kit",
	Long:  "tool kit for study",
}
var testCmd = &cobra.Command{
	Use:   "test",
	Short: "test",
	Long:  "test",
	Run: func(cmd *cobra.Command, args []string) {
		// zipPath := "/tmp/bb/1030553_ZDBROWSING_3_3101041737616999978_1_V2.zip"
		// file, err := os.Open(zipPath)
		// if err != nil {
		// 	fmt.Println(err.Error())
		// 	return
		// }
		// zipInfo, err := file.Stat()
		// if err != nil {
		// 	fmt.Println(err.Error())
		// 	return
		// }
		// fmt.Println(zipInfo.Size())

		// buffer := []byte("abcdef")
		// fmt.Printf("%s, %s\n", buffer[:len(buffer)/2], buffer[len(buffer)/2:])

		ede2Key := []byte("example key 1234")
		var tripleDESKey []byte
		tripleDESKey = append(tripleDESKey, ede2Key[:16]...)
		tripleDESKey = append(tripleDESKey, ede2Key[:8]...)
		fmt.Printf("tripleDESKey: %d\n", len(tripleDESKey))
		desCipher, err := des.NewTripleDESCipher(tripleDESKey)
		if err != nil {
			panic(err)
		}
		var inputData = []byte{0x32, 0x43, 0xf6, 0xa8, 0x88, 0x5a, 0x30, 0x8d, 0x31, 0x31, 0x98, 0xa2, 0xe0, 0x37, 0x07, 0x34}
		out := make([]byte, len(inputData))
		desCipher.Encrypt(out, inputData)
		fmt.Printf("Encrypted data : %#v\n", out) //Encrypted data : []byte{0x39, 0x9e, 0xbe, 0xa9, 0xc3, 0xfa, 0x77, 0x5e, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0}

		plain := make([]byte, len(inputData))
		desCipher.Decrypt(plain, out)
		fmt.Printf("Decrypted data : %#v\n", plain) //Decrypted data : []byte{0x32, 0x43, 0xf6, 0xa8, 0x88, 0x5a, 0x30, 0
	},
}
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
var subCmd = &cobra.Command{
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

var superSubCmd = &cobra.Command{
	Use:   "superSub",
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
			_, err := i.Eval(v)
			if err != nil {
				fmt.Println(err.Error())
				continue
			}
		}
	},
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
	rootCmd.AddCommand(subCmd)
	rootCmd.AddCommand(superSubCmd)
	rootCmd.AddCommand(lenCmd)
	rootCmd.AddCommand(testCmd)
}

func Execute() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}
