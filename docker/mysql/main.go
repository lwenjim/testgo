package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"math/rand"
	"strings"
	"time"

	_ "github.com/go-sql-driver/mysql"
)

func main() {
	db, err := sql.Open("mysql", "root:123456@tcp(127.0.0.1:13306)/test")
	if err != nil {
		fmt.Println(err)
		return
	}
	row, err := db.Query("show databases")
	if err != nil {
		fmt.Println(err)
		return
	}
	data := []string{}
	for row.Next() {
		name := ""
		_ = row.Scan(&name)
		data = append(data, name)
	}
	buffer, err := json.Marshal(data)
	if err != nil {
		fmt.Println(err)
		return
	}
	fmt.Println(string(buffer))

	for i := 0; i < 100; i++ {
		res, err := db.Exec("insert into user values(null, ?, ?)", RandString(10), i+100)
		if err != nil {
			fmt.Println(err)
			return
		}
		id, err := res.LastInsertId()
		if err != nil {
			fmt.Println(err)
			return
		}
		fmt.Printf("id: %v\n", id)
	}
}

func RandString(n int) string {
	var letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
	var (
		letterIDBits       = 6
		letterIDMask int64 = 1<<letterIDBits - 1
		letterIDMax        = 63 / letterIDBits
	)
	var src = rand.NewSource(time.Now().UnixNano())
	sb := strings.Builder{}
	sb.Grow(n)
	for i, cache, remain := n-1, src.Int63(), letterIDMax; i >= 0; {
		if remain == 0 {
			cache, remain = src.Int63(), letterIDMax
		}
		if idx := cache & letterIDMask; idx < int64(len(letters)) {
			sb.WriteByte(letters[idx])
			i--
		}
		cache >>= letterIDBits
		remain--
	}
	return sb.String()
}
