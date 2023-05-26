package main

import (
	"context"
	"crypto/md5"
	"crypto/tls"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
	"net"
	"net/mail"
	"net/smtp"
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
	v1 "k8s.io/api/core/v1"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/kubectl/pkg/scheme"

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

func TestRestfullClient(t *testing.T) {
	config, err := clientcmd.BuildConfigFromFlags("", clientcmd.RecommendedHomeFile)
	println(clientcmd.RecommendedHomeFile)
	if err != nil {
		panic(err)
	}
	config.GroupVersion = &v1.SchemeGroupVersion
	config.NegotiatedSerializer = scheme.Codecs
	config.APIPath = "/api"

	restClient, err := rest.RESTClientFor(config)
	if err != nil {
		panic(err)
	}
	pod := v1.Pod{}
	err = restClient.Get().Namespace("default").Resource("pods").Name("bar-app").Do(context.TODO()).Into(&pod)
	if err != nil {
		println(err)
	} else {
		println(pod.Name)
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

func TestSql(t *testing.T) {
	db, err := sql.Open("mysql", "root@tcp(127.0.0.1:33060)/test")
	assert.Nil(t, err)

	db.SetConnMaxLifetime(time.Minute * 3)
	db.SetMaxOpenConns(10)
	db.SetMaxIdleConns(10)

	getOne := func(id int64) {
		var password, username string

		s2, err5 := db.Prepare("select username, password from user where id = ?")
		assert.Nil(t, err5)

		err = s2.QueryRow(id).Scan(&username, &password)
		assert.Nil(t, err)

		fmt.Printf("username: %s, password: %s\n", username, password)
	}
	getOne(1)

	insertOne := func() int64 {
		password := time.Now().String()

		hash := md5.New()
		_, err := hash.Write([]byte(password))
		assert.Nil(t, err)

		var outData = make([]byte, 22)
		base64.RawStdEncoding.Encode(outData, hash.Sum(nil))
		password = string(outData)

		rand.Seed(time.Now().UnixNano())
		r, err2 := db.Exec("insert into user (username, password) values (?, ?)", RandStringRunes(20), password)
		assert.Nil(t, err2)
		i, err := r.LastInsertId()
		assert.Nil(t, err)
		_, err = r.RowsAffected()
		assert.Nil(t, err)
		return i
	}
	i := insertOne()

	updateOne := func(id int64, mark string) {
		s, err := db.Prepare("update user set mark = ? where id = ?")
		assert.Nil(t, err)
		defer s.Close()
		r2, err := s.Exec(mark, id)
		assert.Nil(t, err)

		_, err = r2.LastInsertId()
		assert.Nil(t, err)
		_, err = r2.RowsAffected()
		assert.Nil(t, err)
	}
	updateOne(i, "1")
	getOne(i)
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
	// emailAddress := "779772852@qq.com"
	emailAddress := "779772852@qq.com"
	pattern := `^(\w+([-+.]\w+)*@\w+([-.]\w+)*\.\w+([-.]\w+)*|1[345789]{1}\\d{9})$`
	reg := regexp.MustCompile(pattern)
	result := reg.MatchString(emailAddress)
	fmt.Printf("result: %v\n", result)
}

func TestSendMail163(t *testing.T) {
	from := "lwenjim@163.com"
	password := "lwenjin163123"
	smtpHost := "smtp.163.com"
	smtpPort := "25"
	auth := smtp.PlainAuth("", from, password, smtpHost)
	to := []string{from}
	msg := []byte(fmt.Sprintf("To: %s\r\n"+
		"Subject: discount Gophers!\r\n"+
		"\r\n"+
		"This is the email body.\r\n", from))
	err := smtp.SendMail(smtpHost+":"+smtpPort, auth, from, to, msg)
	if err != nil {
		fmt.Println(err)
		return
	}
	fmt.Println("Email Sent Successfully!")
}

func TestSmtpSSl(t *testing.T) {
	from := mail.Address{Name: "", Address: "liuwenjin@1foli.com"}
	to := mail.Address{Name: "", Address: "liuwenjin@1foli.com"}

	subj := "This is the email subject"
	body := "This is an example body.\n With two lines."

	headers := make(map[string]string)
	headers["From"] = from.String()
	headers["To"] = to.String()
	headers["Subject"] = subj

	message := ""
	for k, v := range headers {
		message += fmt.Sprintf("%s: %s\r\n", k, v)
	}
	message += "\r\n" + body

	servername := "smtp.exmail.qq.com:465"

	host, _, _ := net.SplitHostPort(servername)

	auth := smtp.PlainAuth("", "liuwenjin@1foli.com", "lwenjin8098098A", host)

	tlsconfig := &tls.Config{
		ServerName: host,
	}

	conn, err := tls.Dial("tcp", servername, tlsconfig)
	if err != nil {
		log.Panic(err)
	}

	c, err := smtp.NewClient(conn, host)
	if err != nil {
		log.Panic(err)
	}

	if err = c.Auth(auth); err != nil {
		log.Panic(err)
	}

	if err = c.Mail(from.Address); err != nil {
		log.Panic(err)
	}

	if err = c.Rcpt(to.Address); err != nil {
		log.Panic(err)
	}

	w, err := c.Data()
	if err != nil {
		log.Panic(err)
	}

	_, err = w.Write([]byte(message))
	if err != nil {
		log.Panic(err)
	}

	err = w.Close()
	if err != nil {
		log.Panic(err)
	}

	_ = c.Quit()
}

func TestGromMysql(t *testing.T) {
	dbName := RandStringRunes(10)
	engine := sqle.NewDefault(ssql.NewDatabaseProvider(
		memory.NewDatabase(dbName),
		information_schema.NewInformationSchemaDatabase(),
	))
	port, err := getFreePort()
	assert.Nil(t, err)
	config := server.Config{
		Protocol: "tcp",
		Address:  fmt.Sprintf("localhost:%d", port),
	}
	s, err := server.NewDefaultServer(config, engine)
	assert.Nil(t, err)

	go func() {
		t2 := s.Start()
		assert.Nil(t, t2)
	}()
	type Product struct {
		gorm.Model
		Code  string
		Price uint
	}
	dsn := fmt.Sprintf("root@tcp(127.0.0.1:%d)/%s", port, dbName)
	fmt.Printf("dsn: %v\n", dsn)
	dsn = fmt.Sprintf("root@tcp(127.0.0.1:%d)/%s", 33060, "test")
	db, err := gorm.Open(OrmMysql.Open(dsn), &gorm.Config{})
	assert.Nil(t, err)

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
