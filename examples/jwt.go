package examples

import (
	"fmt"
	"math/rand"

	"github.com/golang-jwt/jwt/v5"
)

func TestJWT() {
	mapClaims := jwt.MapClaims{
		"iss": "程序员陈明勇",
		"sub": "chenmingyong.cn",
		"aud": "Programmer",
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, mapClaims)
	jwtKey := make([]byte, 32)
	if _, err := rand.Read(jwtKey); err != nil {
		fmt.Println(err)
		return
	}
	jwtStr, err := token.SignedString(jwtKey)
	if err != nil {
		fmt.Println(err)
		return
	}
	fmt.Printf("jwtStr: %v\n", jwtStr)

	mc := jwt.MapClaims{}
	claims, err := jwt.ParseWithClaims(jwtStr, mc, func(t *jwt.Token) (interface{}, error) {
		return jwtKey, nil
	})
	if err != nil {
		fmt.Println(err)
		return
	}
	fmt.Printf("claims: %v\n", claims)
}
