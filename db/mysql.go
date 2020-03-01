package main

import (
	"database/sql"
	"fmt"
	_ "github.com/go-sql-driver/mysql"
)

const (
	mysql_user   = "root"
	mysql_passwd = "123456!@#"
	mysql_ip     = "10.160.5.28"
	mysql_port   = "3306"
	mysql_qyDB   = "course_db"
)

func main() {
	var qID = "1105188833525761"
	tmpAnswer, tmpCodeName := query(qID)
	fmt.Printf("codeName:%s, answer:%s\n", tmpCodeName, tmpAnswer)
}

func query(quitionID string) (string, string) {
	db := getDB()
	var codeName, answer string
	db.QueryRow("SELECT  `name`, lomap_id FROM course_module where module_id=?", quitionID).Scan(&codeName, &answer)
	defer db.Close()
	return answer, codeName
}

func getDB() *sql.DB  {
	str := fmt.Sprintf("%s:%s@tcp(%s:%s)/%s?charset=utf8mb4&timeout=5000ms", mysql_user, mysql_passwd, mysql_ip, mysql_port, mysql_qyDB)
	db, errOpen := sql.Open("mysql", str)
	if errOpen != nil {
		fmt.Println("query Open is error")
	}
	return db
}