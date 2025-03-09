package cmd

import (
	"crypto/des"
	"fmt"

	"github.com/spf13/cobra"
)

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
		fmt.Printf("Encrypted data : %#v\n", out) 
		plain := make([]byte, len(inputData))
		desCipher.Decrypt(plain, out)
		fmt.Printf("Decrypted data : %#v\n", plain) 
	},
}

func init() {
	rootCmd.AddCommand(testCmd)
}
