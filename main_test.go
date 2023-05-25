package main

import (
	"context"
	"crypto/md5"
	"crypto/tls"
	"database/sql"
	"encoding/base64"
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
	"github.com/qustavo/sqlhooks/v2"
	"k8s.io/client-go/informers"

	"github.com/alicebob/miniredis/v2"
	"github.com/go-sql-driver/mysql"
	"github.com/jmoiron/sqlx"
	"github.com/peterhellberg/giphy"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/assert"
	v1 "k8s.io/api/core/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/cache"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/kubectl/pkg/scheme"

	_ "github.com/go-sql-driver/mysql"

	sqle "github.com/dolthub/go-mysql-server"
	ssql "github.com/dolthub/go-mysql-server/sql"
	"github.com/lwenjim/email"
	smtpMock "github.com/mocktools/go-smtp-mock/v2"
)

func TestMain(m *testing.M) {
	m.Run()
}

func Test_aa(t *testing.T) {
	name := 123
	fmt.Printf("name: %v\n", name)

}
func TestGighy(t *testing.T) {

	g := giphy.DefaultClient
	g.APIKey = "xVXd8j7UxP8Lvn8Dn1aLjLAd5EHYGE31"
	g.Rating = "pg-13"
	g.Limit = 30 * 2
	trendings, _ := g.Search([]string{"11"})
	for _, trending := range trendings.Data {
		fmt.Println(trending.MediaURL())
	}

}

func TestClientSet(t *testing.T) {

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

func TestSharedInformerFactory(t *testing.T) {
	config, err := clientcmd.BuildConfigFromFlags("", clientcmd.RecommendedHomeFile)
	if err != nil {
		panic(err)
	}
	clientSet, err := kubernetes.NewForConfig(config)
	if err != nil {
		panic(err)
	}

	factory := informers.NewSharedInformerFactoryWithOptions(clientSet, 0, informers.WithNamespace("default"))
	informer := factory.Core().V1().Pods().Informer()

	_, err = informer.AddEventHandler(cache.ResourceEventHandlerFuncs{
		AddFunc: func(obj interface{}) {
			fmt.Println("Add Event")
		},
		UpdateFunc: func(oldObj, newObj interface{}) {
			fmt.Println("Update Event")
		},
		DeleteFunc: func(obj interface{}) {
			fmt.Println("Delete Event")
		},
	})
	assert.Nil(t, err)

	stopCh := make(chan struct{})
	factory.Start(stopCh)
	factory.WaitForCacheSync(stopCh)
	<-stopCh
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
	/**
	DROP TABLE IF EXISTS `user`;
		CREATE TABLE `user` (
		  `id` int unsigned NOT NULL AUTO_INCREMENT COMMENT '编号',
		  `username` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT '用户名',
		  `password` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT '密码',
		  `mark` varchar(200) COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT '备注',
		  `created_time` timestamp(3) NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
		  `updated_time` timestamp(3) NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '修改时间',
		  PRIMARY KEY (`id`) COMMENT '主键索引',
		  UNIQUE KEY `password` (`password`) USING BTREE COMMENT '唯一索引',
		  KEY `username` (`username`) USING BTREE COMMENT '普通索引',
		  FULLTEXT KEY `ftext` (`mark`) COMMENT '全文索引'
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
	*/

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

func TestMockMysql(t *testing.T) {
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
	sql.Register("mysqlWithHooks", sqlhooks.Wrap(&mysql.MySQLDriver{}, &Hooks{}))
	assert.Nil(t, err)

	dsn := fmt.Sprintf("root@tcp(localhost:%d)/%s", port, dbName)
	db3, _ := sql.Open("mysqlWithHooks", dsn)
	result, err := db3.Exec(`
		CREATE TABLE t_user(
		  id int unsigned NOT NULL AUTO_INCREMENT COMMENT '编号',
		  user_name varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT '用户名',
		  pass_word varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT '密码',
		  mark varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT '备注',
		  created_time timestamp(3) NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '创建时间',
		  updated_time timestamp(3) NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3) COMMENT '修改时间',
		  PRIMARY KEY (id) COMMENT '主键索引',
		  UNIQUE KEY pass_word (pass_word) USING BTREE COMMENT '唯一索引',
		  KEY user_name (user_name) USING BTREE COMMENT '普通索引'
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;	
	`)
	assert.Nil(t, err)

	_, err = result.RowsAffected()
	assert.Nil(t, err)

	dbhelp, err := sqlx.Connect("mysql", dsn)
	assert.Nil(t, err)
	var data []struct {
		Id       sql.NullInt64  `json:"id"`
		UserName sql.NullString `json:"user_name,omitempty" db:"user_name"`
		Password sql.NullString `json:"pass_word,omitempty"  db:"pass_word"`
		Mark     sql.NullString `json:"mark,omitempty"`
	}
	err = dbhelp.Select(&data, "select id, user_name, pass_word, mark from t_user")
	assert.Nil(t, err)

	for index := range data {
		fmt.Printf("id: %v\n", data[index].Id.Int64)
		fmt.Printf("username: %v\n", data[index].UserName.String)
		fmt.Printf("password: %v\n", data[index].Password.String)
		fmt.Printf("mark: %v\n\n", data[index].Mark.String)
	}

	var schema = `
		CREATE TABLE person (
			first_name text,
			last_name text,
			email text
		);
		
		CREATE TABLE place (
			country text,
			city text NULL,
			telcode integer
		)`

	type Person struct {
		FirstName string `db:"first_name"`
		LastName  string `db:"last_name"`
		Email     string
	}

	type Place struct {
		Country string
		City    sql.NullString
		TelCode int
	}

	db, err := sqlx.Connect("mysqlWithHooks", dsn)
	assert.Nil(t, err)

	for _, s := range strings.Split(schema, ";") {
		db.MustExec(s)
	}

	tx := db.MustBegin()
	tx.MustExec("INSERT INTO person (first_name, last_name, email) VALUES (?, ?, ?)", "Jason", "Moiron", "jmoiron@jmoiron.net")
	tx.MustExec("INSERT INTO person (first_name, last_name, email) VALUES (?, ?, ?)", "John", "Doe", "johndoeDNE@gmail.net")
	tx.MustExec("INSERT INTO place (country, city, telcode) VALUES (?, ?, ?)", "United States", "New York", "1")
	tx.MustExec("INSERT INTO place (country, telcode) VALUES (?, ?)", "Hong Kong", "852")
	tx.MustExec("INSERT INTO place (country, telcode) VALUES (?, ?)", "Singapore", "65")
	_, _ = tx.NamedExec("INSERT INTO person (first_name, last_name, email) VALUES (:first_name, :last_name, :email)", &Person{"Jane", "Citizen", "jane.citzen@example.com"})
	_ = tx.Commit()

	people := []Person{}
	_ = db.Select(&people, "SELECT * FROM person ORDER BY first_name ASC")
	jason, john := people[0], people[1]
	fmt.Printf("%#v\n%#v\n", jason, john)

	jason = Person{}
	err = db.Get(&jason, "SELECT * FROM person WHERE first_name=$1", "Jason")
	assert.Nil(t, err)
	fmt.Printf("%#v\n", jason)

	places := []Place{}
	err = db.Select(&places, "SELECT * FROM place ORDER BY telcode ASC")
	if err != nil {
		fmt.Println(err)
		return
	}
	usa, singsing, honkers := places[0], places[1], places[2]
	fmt.Printf("%#v\n%#v\n%#v\n", usa, singsing, honkers)

	place := Place{}
	rows, err := db.Queryx("SELECT * FROM place")
	assert.Nil(t, err)
	for rows.Next() {
		err := rows.StructScan(&place)
		assert.Nil(t, err)
		fmt.Printf("%#v\n", place)
	}

	_, err = db.NamedExec(`INSERT INTO person (first_name,last_name,email) VALUES (:first,:last,:email)`, map[string]interface{}{
		"first": "Bin",
		"last":  "Smuth",
		"email": "bensmith@allblacks.nz",
	})
	assert.Nil(t, err)

	_, err = db.NamedQuery(`SELECT * FROM person WHERE first_name=:fn`, map[string]interface{}{"fn": "Bin"})
	assert.Nil(t, err)

	_, err = db.NamedQuery(`SELECT * FROM person WHERE first_name=:first_name`, jason)
	assert.Nil(t, err)

	personStructs := []Person{
		{FirstName: "Ardie", LastName: "Savea", Email: "asavea@ab.co.nz"},
		{FirstName: "Sonny Bill", LastName: "Williams", Email: "sbw@ab.co.nz"},
		{FirstName: "Ngani", LastName: "Laumape", Email: "nlaumape@ab.co.nz"},
	}
	_, err = db.NamedExec(`INSERT INTO person (first_name, last_name, email) VALUES (:first_name, :last_name, :email)`, personStructs)
	assert.Nil(t, err)

	personMaps := []map[string]interface{}{
		{"first_name": "Ardie", "last_name": "Savea", "email": "asavea@ab.co.nz"},
		{"first_name": "Sonny Bill", "last_name": "Williams", "email": "sbw@ab.co.nz"},
		{"first_name": "Ngani", "last_name": "Laumape", "email": "nlaumape@ab.co.nz"},
	}
	_, err = db.NamedExec(`INSERT INTO person (first_name, last_name, email) VALUES (:first_name, :last_name, :email)`, personMaps)
	assert.Nil(t, err)

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

func TestSendMailQQ(t *testing.T) {
	from := os.Getenv("IMail")
	password := os.Getenv("IMailPassword")

	fmt.Printf("from: %v\n", from)
	fmt.Printf("password: %v\n", password)

	to := []string{
		os.Getenv("IMail"),
	}
	smtpHost := "smtp.exmail.qq.com"
	smtpPort := "465" // 465 / 587 / 25 / 465
	message := []byte("This is a test email message.")

	auth := smtp.PlainAuth("", from, password, smtpHost)
	err := smtp.SendMail(smtpHost+":"+smtpPort, auth, from, to, message)

	if err != nil {
		fmt.Println(err)
		return
	}
	fmt.Println("Email Sent Successfully!")
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

func TestSmtpWithTls(t *testing.T) {
	e := email.NewEmail()
	e.From = "Jordan Wright <liuwenjin@1foli.com>"
	e.To = []string{"liuwenjin@1foli.com"}
	e.Bcc = []string{"liuwenjin@1foli.com"}
	e.Cc = []string{"liuwenjin@1foli.com"}
	e.Subject = "Awesome Subject"
	e.Text = []byte("Text Body is, of course, supported!")
	e.HTML = []byte("<h1>Fancy HTML is supported, too!</h1>")
	err := e.Send("smtp.exmail.qq.com:587", smtp.PlainAuth("", "liuwenjin@1foli.com", "lwenjin8098098A", "smtp.exmail.qq.com"))
	assert.Nil(t, err)
}

func TestSendMailTls(t *testing.T) {
	// You can pass empty smtpMock.ConfigurationAttr{}. It means that smtpMock will use default settings
	s := smtpMock.New(smtpMock.ConfigurationAttr{
		LogToStdout:       true,
		LogServerActivity: true,
	})

	// To start s use Start() method
	if err := s.Start(); err != nil {
		fmt.Println(err)
	}

	// Server's port will be assigned dynamically after s.Start()
	// for case when portNumber wasn't specified
	hostAddress, portNumber := "127.0.0.1", s.PortNumber()

	// Possible SMTP-client stuff for iteration with mock s
	address := fmt.Sprintf("%s:%d", hostAddress, portNumber)
	timeout := time.Duration(2) * time.Second

	connection, _ := net.DialTimeout("tcp", address, timeout)
	client, _ := smtp.NewClient(connection, hostAddress)
	err := client.Hello("example.com")
	assert.Nil(t, err)
	err = client.Quit()
	assert.Nil(t, err)
	err = client.Close()
	assert.Nil(t, err)

	// Each result of SMTP session will be saved as message.
	// To get access to s messages use Messages() method
	s.Messages()

	// To stop the s use Stop() method. Please note, smtpMock uses graceful shutdown.
	// It means that smtpMock will end all sessions after client responses or by session
	// timeouts immediately.
	if err := s.Stop(); err != nil {
		fmt.Println(err)
	}
}

func TestMockSmtp(t *testing.T) {
	s := smtpMock.New(smtpMock.ConfigurationAttr{
		LogToStdout:       true,
		LogServerActivity: true,
	})

	if err := s.Start(); err != nil {
		fmt.Println(err)
	}

	hostAddress, portNumber := "127.0.0.1", s.PortNumber()

	address := fmt.Sprintf("%s:%d", hostAddress, portNumber)
	timeout := time.Duration(2) * time.Second

	connection, _ := net.DialTimeout("tcp", address, timeout)
	client, _ := smtp.NewClient(connection, hostAddress)
	err := client.Hello("example.com")
	assert.Nil(t, err)
	err = client.Quit()
	assert.Nil(t, err)
	err = client.Close()
	assert.Nil(t, err)

	s.Messages()

	if err := s.Stop(); err != nil {
		fmt.Println(err)
	}
}
