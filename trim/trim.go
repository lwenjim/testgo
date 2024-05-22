package main

import (
	"encoding/json"
	"fmt"
	"log"
	"strings"
)

type trim string

func (t *trim) UnmarshalJSON(data []byte) error {
	var s string
	if err := json.Unmarshal(data, &s); err != nil {
		return err
	}
	*t = trim(strings.TrimSpace(s))
	fmt.Printf("these are the strings: '%s'\n", *t)
	return nil
}

func TestTrim() {
	type user struct {
		Name  trim `json:"name"`
		Email trim `json:"email"`
	}
	var users user
<<<<<<< HEAD
	newUser := `{"name":"random", "email":"random@.        "}`
=======
	newUser := `{"name":"random", "email":"random@."}`
>>>>>>> 6bb84f2172ac498843462bbc3150bf510c348af7
	if err := json.Unmarshal([]byte(newUser), &users); err != nil {
		log.Fatal(err)
	}
	fmt.Printf("%s\n", users)
	fmt.Println(123)
}
