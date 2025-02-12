package main

import (
	"crypto/cipher"
	"fmt"

	"github.com/emmansun/gmsm/padding"
	"github.com/tjfoc/gmsm/sm4"
)

func main2() {
	// Load your secret key from a safe place and reuse it across multiple
	// NewCipher calls. (Obviously don't use this example key for anything
	// real.) If you want to convert a passphrase to a key, use a suitable
	// package like bcrypt or scrypt.
	key := []byte("1234567890abcdef")
	plaintext := []byte("sm4 exampleplaintext")

	block, err := sm4.NewCipher(key)
	if err != nil {
		panic(err)
	}

	// CBC mode works on blocks so plaintexts may need to be padded to the
	// next whole block. For an example of such padding, see
	// https://tools.ietf.org/html/rfc5246#section-6.2.3.2.
	pkcs7 := padding.NewPKCS7Padding(sm4.BlockSize)
	paddedPlainText := pkcs7.Pad(plaintext)

	// The IV needs to be unique, but not secure. Therefore it's common to
	// include it at the beginning of the ciphertext.
	ciphertext := make([]byte, len(paddedPlainText))
	iv := []byte("0000000000000000")
	// if _, err := io.ReadFull(rand.Reader, iv); err != nil {
	// 	panic(err)
	// }

	mode := cipher.NewCBCEncrypter(block, iv)
	mode.CryptBlocks(ciphertext, paddedPlainText)

	fmt.Printf("%x\n", ciphertext)

	// 解密
	{
		// // Load your secret key from a safe place and reuse it across multiple
		// // NewCipher calls. (Obviously don't use this example key for anything
		// // real.) If you want to convert a passphrase to a key, use a suitable
		// // package like bcrypt or scrypt.
		// key := []byte("1234567890abcdef")
		// // ciphertext, _ := hex.DecodeString("8c72fa350ea02e0d1e7896a7ed6dec4c6de49e1491d673b866ec7e19fdf65b1e")

		// block, err := sm4.NewCipher(key)
		// if err != nil {
		// 	panic(err)
		// }

		// // The IV needs to be unique, but not secure. Therefore it's common to
		// // include it at the beginning of the ciphertext.
		// if len(ciphertext) < sm4.BlockSize {
		// 	panic("ciphertext too short")
		// }
		// // iv := []byte("0000000000000000")
		// // ciphertext = ciphertext[sm4.BlockSize:]

		// mode := cipher.NewCBCDecrypter(block, iv)

		// // CryptBlocks can work in-place if the two arguments are the same.
		// mode.CryptBlocks(ciphertext, ciphertext)

		// // Unpad plaintext
		// pkcs7 := padding.NewPKCS7Padding(sm4.BlockSize)
		// ciphertext, err = pkcs7.Unpad(ciphertext)
		// if err != nil {
		// 	panic(err)
		// }
		// fmt.Printf("ciphertext: %v\n", string(ciphertext))
	}
}
