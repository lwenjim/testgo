package main

import (
	"context"
	"encoding/json"
	"fmt"
	"math/rand"
	"net"
	"net/url"
	"os"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/bitly/go-simplejson"
	"github.com/dolthub/go-mysql-server/memory"
	"github.com/dolthub/go-mysql-server/server"
	"github.com/dolthub/go-mysql-server/sql/information_schema"
	OrmMysql "gorm.io/driver/mysql"
	"gorm.io/gorm"

	"github.com/alicebob/miniredis/v2"
	"github.com/peterhellberg/giphy"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/assert"

	_ "github.com/go-sql-driver/mysql"

	sqle "github.com/dolthub/go-mysql-server"
	ssql "github.com/dolthub/go-mysql-server/sql"
)

func TestMain(m *testing.M) {
	m.Run()
}

func TestGighy(t *testing.T) {

	g := giphy.DefaultClient
	g.APIKey = "xVXd8j7UxP8Lvn8Dn1aLjLAd5EHYGE31"
	g.Rating = "pg-13"
	g.Limit = 2
	trendings, _ := g.Search([]string{"11"})
	for _, trending := range trendings.Data {
		fmt.Println(trending.MediaURL())
	}

}

func TestGeneralSql(t *testing.T) {
	lMap := map[string]uint8{
		"短信":   0,
		"电话铃声": 1,
	}
	path := "/Users/jim/Library/Application Support/jspp/4185955/message/834c38e419a387453405f67c1373d052c9a13902/file/75688595411f66de667cb8a4560ca1cc18b40b1a/铃声-2/"
	var values []string
	for key, val := range lMap {
		dirEntries, err := os.ReadDir(path + key)
		if err != nil {
			continue
		}
		for _, entry := range dirEntries {
			split := strings.Split(entry.Name(), "-")
			remoteUrl := "/phonesound/%E9%93%83%E5%A3%B0-2/" + url.QueryEscape(key+"/"+entry.Name())
			sqlQuery := "insert into  `jspp`.`t_push_phone_sound` (`name`, `url`, `sound_type`, `channel_type`) VALUES ('%s', '%s', %d, %d)"
			values = append(values, fmt.Sprintf(sqlQuery, split[0], remoteUrl, val, 1))
		}
	}
	println(strings.Join(values, "\n"))
}

func TestString(t *testing.T) {
	s := "abc"
	s = s[:0]
	fmt.Printf("s: %v\n", s)
}

func TestRedis(t *testing.T) {
	s, err := miniredis.Run()
	if err != nil {
		panic(err)
	}

	rdb := redis.NewClient(&redis.Options{
		Addr:     s.Addr(),
		Password: "",
		DB:       0,
	})

	var ctx = context.Background()

	err = rdb.Set(ctx, "key", "value", 10*time.Minute).Err()
	assert.Nil(t, err)

	val, err := rdb.Get(ctx, "key").Result()
	assert.Nil(t, err)
	fmt.Println("key", val)
}

func RandStringRunes(n int) string {
	var letterRunes = []rune("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
	b := make([]rune, n)
	for i := range b {
		b[i] = letterRunes[rand.Intn(len(letterRunes))]
	}
	return string(b)
}

type Hooks struct{}

func (h *Hooks) Before(ctx context.Context, query string, args ...interface{}) (context.Context, error) {
	type GolbalValue string
	var name GolbalValue = "begin"
	fmt.Printf("> %s %q", query, args)
	return context.WithValue(ctx, name, time.Now()), nil
}

func (h *Hooks) After(ctx context.Context, query string, args ...interface{}) (context.Context, error) {
	begin := ctx.Value("begin").(time.Time)
	fmt.Printf(". took: %s\n", time.Since(begin))
	return ctx, nil
}

func getFreePort() (port int, err error) {
	var a *net.TCPAddr
	if a, err = net.ResolveTCPAddr("tcp", "localhost:0"); err == nil {
		var l *net.TCPListener
		if l, err = net.ListenTCP("tcp", a); err == nil {
			defer l.Close()
			return l.Addr().(*net.TCPAddr).Port, nil
		}
	}
	return
}

func TestJson(t *testing.T) {
	js, _ := simplejson.NewJson([]byte("{\"authToken\":\"abc\"}"))
	fmt.Println(js.Get("authToken").String())
}

func TestStructSlice(t *testing.T) {
	type book struct {
		Name  string `json:"name"`
		Count int    `json:"count"`
	}

	data := []book{
		{
			Name:  "golang",
			Count: 11,
		},
		{
			Name:  "java",
			Count: 21,
		},
	}

	fmt.Printf("%+v\n", data)
}

func TestPhoneEmail(t *testing.T) {
	emailAddress := "779772852@qq.com"
	pattern := `^(\w+([-+.]\w+)*@\w+([-.]\w+)*\.\w+([-.]\w+)*|1[345789]{1}\\d{9})$`
	reg := regexp.MustCompile(pattern)
	result := reg.MatchString(emailAddress)
	fmt.Printf("result: %v\n", result)
}

func TestGromMysql(t *testing.T) {
	dsn, err := startTempMysqlServer()
	assert.Nil(t, err)
	db, err := gorm.Open(OrmMysql.Open(*dsn), &gorm.Config{})
	assert.Nil(t, err)
	type Product struct {
		gorm.Model
		Code  string
		Price uint
	}
	err = db.AutoMigrate(&Product{})
	assert.Nil(t, err)

	db.Create(&Product{
		Code:  "D42",
		Price: 100,
	})

	var product Product
	db.First(&product, 1)

	buf, err := json.Marshal(product)
	assert.Nil(t, err)

	fmt.Printf("product: %v\n", string(buf))
}

func startTempMysqlServer() (*string, error) {
	dbName := RandStringRunes(10)
	engine := sqle.NewDefault(ssql.NewDatabaseProvider(
		memory.NewDatabase(dbName),
		information_schema.NewInformationSchemaDatabase(),
	))
	port, err := getFreePort()
	if err != nil {
		return nil, err
	}
	config := server.Config{
		Protocol: "tcp",
		Address:  fmt.Sprintf("localhost:%d", port),
	}
	s, err := server.NewDefaultServer(config, engine)
	if err != nil {
		return nil, err
	}

	go func() {
		_ = s.Start()
	}()

	dsn := fmt.Sprintf("root@tcp(127.0.0.1:%d)/%s", port, dbName)
	return &dsn, nil
}
