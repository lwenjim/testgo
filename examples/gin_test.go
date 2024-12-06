package examples

import (
	"encoding/json"
	"io"

	"context"
	"database/sql"
	"fmt"
	"net/http"
	"sync"
	"testing"
	"time"

	"github.com/gin-gonic/gin"

	_ "github.com/go-sql-driver/mysql"
)

func TestGin(t *testing.T) {
	r := gin.Default()
	r.GET("/ping", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"message": "pong",
		})
	})
	type Param struct {
		Name string `json:"name,omitempty" form:"name"`
	}
	r.POST("/test", func(context *gin.Context) {
		var p Param
		if err := context.ShouldBind(&p); err != nil {
			fmt.Println(err)
			return
		}
		buff, _ := json.Marshal(p)
		context.JSON(http.StatusOK, string(buff))
	})
	_ = r.Run()
}

// 模拟一些私人数据
var secrets = gin.H{
	"foo":    gin.H{"email": "foo@bar.com", "phone": "123433"},
	"austin": gin.H{"email": "austin@example.com", "phone": "666"},
	"lena":   gin.H{"email": "lena@guapa.com", "phone": "523443"},
}

func TestMain(t *testing.T) {
	r := gin.Default()

	// 路由组使用 gin.BasicAuth() 中间件
	// gin.Accounts 是 map[string]string 的一种快捷方式
	authorized := r.Group("admin", gin.BasicAuth(gin.Accounts{
		"foo":    "bar",
		"austin": "1234",
		"lena":   "hello2",
		"manu":   "4321",
	}))

	// /admin/secrets 端点
	// 触发 "localhost:8080/admin/secrets
	authorized.GET("secrets", func(c *gin.Context) {
		// 获取用户，它是由 BasicAuth 中间件设置的
		user := c.MustGet(gin.AuthUserKey).(string)
		if secret, ok := secrets[user]; ok {
			c.JSON(http.StatusOK, gin.H{"user": user, "secret": secret})
		} else {
			c.JSON(http.StatusOK, gin.H{"user": user, "secret": "NO SECRET :("})
		}
	})
	authorized.GET("secrets/abc", func(c *gin.Context) {
		c.JSON(http.StatusOK, nil)
	})

	// 监听并在 0.0.0.0:8080 上启动服务
	_ = r.Run(":8080")
}

func TestMain2(t *testing.T) {
	client := http.DefaultClient
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, "https://www.example.com", nil)
	if err != nil {
		fmt.Println(err)
		return
	}

	resp, err := client.Do(req)
	if err != nil {
		fmt.Println(err)
		return
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		fmt.Println(err)
		return
	}

	fmt.Println(string(body))
}

func TestMain3(t *testing.T) {
	parent := context.Background()
	// ctx, cancel := context.WithCancel(parent)
	// ctx, cancel := context.WithDeadline(parent, time.Now().Add(4*time.Second))
	ctx, cancel := context.WithTimeout(parent, 4*time.Second)
	go func() {
		select {
		case <-ctx.Done():
			fmt.Println(ctx.Err())
			return
		case <-time.After(5 * time.Second):
			fmt.Println("work done")
		}
	}()
	time.Sleep(10 * time.Second)
	cancel()
	time.Sleep(1 * time.Second)
}

func TestMain4(t *testing.T) {
	type userKey struct{}
	parent := context.Background()
	ctx := context.WithValue(parent, userKey{}, "admin")
	name := "lwenjim"
	go func() {
		if user, ok := ctx.Value(userKey{}).(string); ok {
			fmt.Printf("user is %s, %s\n", user, name)
		} else {
			fmt.Println("user is not found")
		}
	}()
	select {}
}

func TestMain5(t *testing.T) {
	db, err := sql.Open("mysql", "root:12345678@tcp(localhost:33066)/test")
	if err != nil {
		panic(err)
	}
	defer db.Close()

	ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
	defer cancel()
	const maxConn = 5
	connCh := make(chan *sql.Conn, maxConn)
	var wg sync.WaitGroup
	for i := 0; i < maxConn; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for {
				select {
				case <-ctx.Done():
					return
				default:
					if len(connCh) < maxConn {
						conn, err := db.Conn(ctx)
						if err != nil {
							fmt.Println(err)
							return
						}
						connCh <- conn
					}
				}
			}
		}()
	}
	wg.Wait()
	fmt.Println(123)
}
