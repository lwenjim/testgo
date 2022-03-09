package main

import (
	"fmt"
	"strings"

	"github.com/go-redis/redis"
	_ "github.com/go-sql-driver/mysql"
)

func main() {
	redis := redis.NewClient(&redis.Options{Addr: "127.0.0.1:6379"})

	for message := range redis.PSubscribe("abc").Channel() {
		fmt.Printf("payload:%s, channel:%s\n", message.Payload, message.Channel)
	}

	redis.Publish("abc", "123")

	res, _ := redis.PubSubChannels("*").Result()
	println(strings.Join(res, ""))

	//message := redis.Subscribe("a")
	//defer message.Close()
	//for msg := range message.Channel() {
	//	fmt.Printf("channel:%s, payLoad:%s", msg.Channel, msg.Payload)
	//}

	//pipe := redis.TxPipeline()
	//defer pipe.Close()
	//pipe.Set("lwenjim", "aaa", 0)
	//pipe.Exec()
	//result, _ := redis.Get("lwenjim").Result()
	//println(result)

	//res, _ := redis.Eval("return redis.call('get', KEYS[1])", []string{"a"}).String()
	//println(res)

	//res := redis.ScriptLoad("return redis.call('get', KEYS[1])").String()
	//res2, _ := redis.EvalSha("4e6d8fc8bb01276962cce5371fa795a7763657ae", []string{"a"}).String()
	//println(res2)

	//println(redis.Time().String())

	//println(redis.Info().String())

	//println(redis.DBSize().String())

	//println(redis.ClientList().String())

	//println(redis.ClientGetName().String())

	//println(redis.RandomKey().String())

	//type CourseModel struct {
	//	CourseId   string
	//	CourseName string
	//}
	//var list map[string]int
	//list = make(map[string]int)
	//db, _ := sql.Open("mysql", "root:123456!@#@tcp(localhost-dev:3306)/course_db?charset=utf8")
	//rows, _ := db.Query("select course_id,course_name from course limit 1")
	//for rows.Next() {
	//	var course_id int
	//	var course_name string
	//	//rows.Columns()
	//	_ = rows.Scan(&course_id, &course_name)
	//	list[course_name] = course_id
	//}
	//for k, v := range list {
	//	println(k, v)
	//}

	//var list map[string]int
	//list = make(map[string]int)
	//db, _ := sql.Open("mysql", "root:123456!@#@tcp(localhost-dev:3306)/course_db?charset=utf8")
	//tx, _ := db.Begin()
	//rows, _ := tx.Query("select course_id,course_name from course limit 1")
	//for rows.Next() {
	//	var course_id int
	//	var course_name string
	//	//rows.Columns()
	//	_ = rows.Scan(&course_id, &course_name)
	//	list[course_name] = course_id
	//}
	//for k, v := range list {
	//	println(k, v)
	//}

	// t := time.Now().Unix()
	// c := 0
	// for i := 0; i < 100000000; i++ {
	// 	if time.Now().Unix() > t+1 {
	// 		break
	// 	}
	// 	c++
	// }
	// a := 0
	// println(a)
}
