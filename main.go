package main

import (
	"encoding/json"
	"fmt"
	"log"
	"strings"
)

// hello world
// say hello
type user struct {
	Name  trim `json:"name"`
	Email trim `json:"email"`
}

/*
 * ni hao
 * bu ke yi
 */
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

func main() {
	var users user
	newUser := `{"name":"random", "email":"random@.        "}`
	if err := json.Unmarshal([]byte(newUser), &users); err != nil {
		log.Fatal(err)
	}
	fmt.Printf("%s", users)
}
