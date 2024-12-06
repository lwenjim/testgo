package examples

import (
	"encoding/json"
	"fmt"
	"log"
	"strings"
	"testing"
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

func TestTrim(t *testing.T) {
	type user struct {
		Name  trim `json:"name"`
		Email trim `json:"email"`
	}
	var users user
	newUser := `{"name":"  random    ", "email":" random "}`
	if err := json.Unmarshal([]byte(newUser), &users); err != nil {
		log.Fatal(err)
	}
	fmt.Printf("%s\n", users)
	fmt.Println(123)
}
