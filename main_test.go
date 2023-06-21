package main

import (
	"bytes"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"math/rand"
	"net"
	"net/url"
	"os"
	"reflect"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/bitly/go-simplejson"
	"github.com/dolthub/go-mysql-server/memory"
	"github.com/dolthub/go-mysql-server/server"
	"github.com/dolthub/go-mysql-server/sql/information_schema"
	"github.com/spf13/pflag"
	"github.com/spf13/viper"
	"gopkg.in/validator.v2"
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

	str, err := rdb.Set(ctx, "abc", 123, time.Hour*12).Result()
	assert.Nil(t, err)
	fmt.Printf("result:%s\n", str)

	i, err := rdb.Exists(ctx, "abc").Result()
	assert.Nil(t, err)
	fmt.Printf("%+v\n", i)
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

func TestRuntime(t *testing.T) {
	fmt.Println(runtime.GOMAXPROCS(0) + 1)
}

func TestViper(t *testing.T) {
	viper.SetDefault("ContentDir", "content")
	viper.SetDefault("LayoutDir", "layouts")
	viper.SetDefault("Taxonomies", map[string]string{"tag": "tags", "category": "categories"})

	viper.SetConfigName("config")      // name of config file (without extension)
	viper.SetConfigType("yaml")        // REQUIRED if the config file does not have the extension in the name
	viper.AddConfigPath("/Users/jim/") // path to look for the config file in
	viper.AddConfigPath(".")           // optionally look for config in the working directory
	err := viper.ReadInConfig()        // Find and read the config file
	assert.Nil(t, err)

	viper.SetConfigType("yaml") // or viper.SetConfigType("YAML")

	// any approach to require this configuration into your program.
	var yamlExample = []byte(`
Hacker: true
name: steve
hobbies:
- skateboarding
- snowboarding
- go
clothing:
jacket: leather
trousers: denim
age: 35
eyes : brown
beard: true
`)

	_ = viper.ReadConfig(bytes.NewBuffer(yamlExample))

	fmt.Println(viper.Get("name"))

	viper.RegisterAlias("loud", "Verbose")

	viper.Set("verbose", true) // same result as next line
	viper.Set("loud", true)    // same result as prior line

	fmt.Printf("%+v\n", viper.GetBool("loud"))    // true
	fmt.Printf("%+v\n", viper.GetBool("verbose")) // true

	viper.SetEnvPrefix("spf") // will be uppercased automatically
	_ = viper.BindEnv("id")

	os.Setenv("SPF_ID", "13") // typically done outside of the app

	id := viper.Get("id") // 13
	fmt.Println(id)

	// using standard library "flag" package
	flag.Int("flagname", 1234, "help message for flagname")

	pflag.CommandLine.AddGoFlagSet(flag.CommandLine)
	pflag.Parse()
	_ = viper.BindPFlags(pflag.CommandLine)

	i := viper.GetInt("flagname") // retrieve value from viper
	fmt.Println(i)
}

func TestDemo(t *testing.T) {
	// print(144536398 - 143878550 - 400000 - 24800 - 4700 - 36000*3)
	// println("  ")
	// print(1900 - 1440 - 100 + 180)
	// println(time.Now().AddDate(0, -1, 0).Format("200601"))
	// println(500 / 187)
	iMap := map[string]string{
		"abc": "123",
	}
	iMap["ddd"] = "111"
	for k, v := range iMap {
		println(k)
		println(v)
	}
}

func TestValidate(t *testing.T) {
	in := struct {
		UserID           uint64 `protobuf:"varint,1,opt,name=user_id,json=userId,proto3" json:"user_id,omitempty" db:"user_id"`
		Birthday         int64  `protobuf:"varint,2,opt,name=birthday,proto3" json:"birthday,omitempty" db:"birthday"`
		Gender           int32  `protobuf:"varint,3,opt,name=gender,proto3" json:"gender,omitempty" db:"gender" validate:"min=-1,max=2"`
		VerifyStatus     int32  `protobuf:"varint,4,opt,name=verify_status,json=verifyStatus,proto3" json:"verify_status,omitempty" db:"verify_status" validate:"min=-1, max=1"`
		HandVerifyStatus string `protobuf:"varint,5,opt,name=hand_verify_status,json=handVerifyStatus,proto3" json:"hand_verify_status,omitempty" db:"hand_verify_status" validate:"in=1    2"`
	}{
		UserID:           0,
		Birthday:         0,
		Gender:           0,
		VerifyStatus:     0,
		HandVerifyStatus: "2",
	}
	err := validator.Validate(in)
	assert.Nil(t, err)
}

func ValidateInt[T int8 | uint8 | int16 | uint16 | int | uint | int32 | uint32 | int64 | uint64](param string, v interface{}) error {
	strs := strings.Split(param, " ")
	for _, s := range strs {
		s = strings.Trim(s, " ")
		if len(s) == 0 {
			continue
		}
		if newV, ok := v.(T); ok {
			newS, err := strconv.Atoi(s)
			if err != nil {
				return err
			}
			if T(newS) == newV {
				return nil
			}
		}
	}
	return validator.ErrUnsupported
}

func init() {
	_ = validator.SetValidationFunc("in", func(v interface{}, param string) error {
		st := reflect.ValueOf(v)
		err := fmt.Errorf("error type")
		switch st.Kind() {
		case reflect.Int:
			err = ValidateInt[int](param, v)
		case reflect.Uint:
			err = ValidateInt[uint](param, v)
		case reflect.Int8:
			err = ValidateInt[int8](param, v)
		case reflect.Uint8:
			err = ValidateInt[uint8](param, v)
		case reflect.Uint16:
			err = ValidateInt[uint16](param, v)
		case reflect.Int16:
			err = ValidateInt[int16](param, v)
		case reflect.Int32:
			err = ValidateInt[int32](param, v)
		case reflect.Uint32:
			err = ValidateInt[uint32](param, v)
		case reflect.Int64:
			err = ValidateInt[int64](param, v)
		case reflect.Uint64:
			err = ValidateInt[uint64](param, v)
		case reflect.String:
			strs := strings.Split(param, " ")
			for _, s := range strs {
				s = strings.Trim(s, " ")
				if len(s) == 0 {
					continue
				}
				newV, _ := v.(string)
				if s == newV {
					return nil
				}
			}
		}
		return err
	})
}
