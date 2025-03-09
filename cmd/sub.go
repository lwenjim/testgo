package cmd

import (
	"fmt"
	"reflect"
	"regexp"
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
			reStr := `(?P<operate>%|\*|\+|-|/)`
			// co, err := regexp.Compile(reStr)
			// if err != nil {
			// 	fmt.Println(err.Error())
			// 	continue
			// }
			// res := co.ReplaceAllFunc([]byte(v), func(b []byte) []byte {
			// 	b = append([]byte(` `), b...)
			// 	return append(b, ' ')
			// })
			// res := co.ReplaceAllString(v, " $1 ")
			// res := co.ReplaceAllStringFunc(v, func(s string) string {
			// 	submatchs := co.FindStringSubmatch(s)
			// 	return fmt.Sprintf(" %s ", strings.ToUpper(submatchs[1]))
			// })
			re := regexp.MustCompile(reStr)
			res := re.ReplaceAllString(v, " ${operate} ")
			v := reflect.ValueOf(val.Interface())
			var result float64
			switch v.Kind() {
			case reflect.Int, reflect.Int32, reflect.Int64:
				result = float64(v.Int())
			case reflect.Float32, reflect.Float64:
				result = v.Float()
			case reflect.String:
				fmt.Println(v.Interface().(string))
			default:
				panic(fmt.Sprintf("error kind: %s", v.Kind()))
			}
			if result > 0 {
				fmt.Printf("%s = %.3f\n", res, result)
			}
		}
	},
}

func init() {
	rootCmd.AddCommand(subCmd)
}
