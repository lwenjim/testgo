package main

import (
	"context"
	"database/sql"
	"testing"

	_ "github.com/go-sql-driver/mysql"
)

func Test_mysql(t *testing.T) {
	db, err := sql.Open("mysql", "root@:3306/test")
	if err != nil {
		println(err)
		return
	}
	_, err = db.Conn(context.Background())
	if err != nil {
		println(err)
		return
	}
	//conn.ExecContext(context.Background(), "insert into user()")
}
