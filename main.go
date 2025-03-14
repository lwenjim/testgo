package main

import (
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/pem"
	"errors"
	"fmt"
	"io/ioutil"
)

func main() {
	// 加载私钥
	privateKey, err := loadPrivateKey("private.pem")
	if err != nil {
		panic(err)
	}

	// 待签名的消息
	message := []byte("Hello, RSA-PSS!")

	// 计算SHA256哈希
	hashed := sha256.Sum256(message)

	// 配置PSS参数
	opts := &rsa.PSSOptions{
		SaltLength: rsa.PSSSaltLengthEqualsHash, // 盐长度等于哈希长度
		Hash:       crypto.SHA256,               // 指定哈希函数
	}

	// 生成签名
	signature, err := rsa.SignPSS(rand.Reader, privateKey, crypto.SHA256, hashed[:], opts)
	if err != nil {
		panic(err)
	}

	fmt.Printf("Signature: %x\n", signature)
}

// 加载PEM格式的RSA私钥
func loadPrivateKey(path string) (*rsa.PrivateKey, error) {
	// 读取私钥文件
	privKeyData, err := ioutil.ReadFile(path)
	if err != nil {
		return nil, err
	}

	// 解码PEM块
	block, _ := pem.Decode(privKeyData)
	if block == nil {
		return nil, errors.New("failed to parse PEM block")
	}

	// 解析私钥
	switch block.Type {
	case "RSA PRIVATE KEY": // PKCS#1格式
		return x509.ParsePKCS1PrivateKey(block.Bytes)
	case "PRIVATE KEY": // PKCS#8格式
		key, err := x509.ParsePKCS8PrivateKey(block.Bytes)
		if err != nil {
			return nil, err
		}
		privKey, ok := key.(*rsa.PrivateKey)
		if !ok {
			return nil, errors.New("not an RSA private key")
		}
		return privKey, nil
	default:
		return nil, fmt.Errorf("unsupported key type: %q", block.Type)
	}
}
