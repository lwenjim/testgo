package main

import (
	"context"
	"crypto/md5"
	"database/sql"
	"encoding/base64"
	"fmt"
	"math/rand"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/jmoiron/sqlx"
	"github.com/stretchr/testify/assert"

	"k8s.io/client-go/informers"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/cache"

	"github.com/peterhellberg/giphy"
	v1 "k8s.io/api/core/v1"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/kubectl/pkg/scheme"

	_ "github.com/go-sql-driver/mysql"
)

func TestMain(m *testing.M) {
	m.Run()
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
	if err != nil {
		panic(err)
	}

	stopCh := make(chan struct{})
	factory.Start(stopCh)
	factory.WaitForCacheSync(stopCh)
	<-stopCh
}

func TestGeneralSql(t *testing.T) {
	lMap := map[string]uint8{
		"短信":     0,
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
			values = append(values, fmt.Sprintf("INSERT INTO `jspp`.`t_push_phone_sound` (`name`, `url`, `sound_type`, `channel_type`) VALUES ('%s', '%s', %d, %d);", split[0], remoteUrl, val, 1))
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

}

func TestSqlx(t *testing.T) {
	d, err := sqlx.Open("mysql", "root@tcp(127.0.0.1:33060)/test")
	assert.Nil(t, err)
	var data []struct {
		Id       sql.NullInt64  `json:"id"`
		UserName sql.NullString `json:"username,omitempty"`
		Password sql.NullString `json:"password,omitempty"`
		Mark     sql.NullString `json:"mark,omitempty"`
	}
	err = d.Select(&data, "select id, username, password, mark from user")
	assert.Nil(t, err)

	for index := range data {
		fmt.Printf("id: %v\n", data[index].Id.Int64)
		fmt.Printf("username: %v\n", data[index].UserName.String)
		fmt.Printf("password: %v\n", data[index].Password.String)
		fmt.Printf("mark: %v\n\n", data[index].Mark.String)
	}
}

func RandStringRunes(n int) string {
	var letterRunes = []rune("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
	b := make([]rune, n)
	for i := range b {
		b[i] = letterRunes[rand.Intn(len(letterRunes))]
	}
	return string(b)
}
