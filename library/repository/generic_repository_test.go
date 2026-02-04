package repository

import (
	"context"
	"fmt"
	"log"
	"net"
	"testing"

	sqle "github.com/dolthub/go-mysql-server"
	"github.com/dolthub/go-mysql-server/memory"
	"github.com/dolthub/go-mysql-server/server"
	"github.com/dolthub/go-mysql-server/sql"
	"github.com/stretchr/testify/assert"
	"gorm.io/driver/mysql"
	"gorm.io/gorm"
)

func TestDatabase(t *testing.T) {
	port, err := GetFreePort()
	assert.Nil(t, err)

	config := server.Config{
		Protocol: "tcp",
		Address:  fmt.Sprintf("localhost:%d", port),
	}
	engine := sqle.NewDefault(sql.NewDatabaseProvider(memory.NewDatabase("test")))
	mysqlLocalServer, err := server.NewDefaultServer(config, engine)
	assert.Nil(t, err)
	go func() {
		if err := mysqlLocalServer.Start(); err != nil {
			panic(err)
		}
	}()

	// 初始化数据库
	dsn := fmt.Sprintf("root:@tcp(127.0.0.1:%d)/test?charset=utf8mb4&parseTime=True&loc=Local", port)
	db, err := gorm.Open(mysql.Open(dsn), &gorm.Config{})
	if err != nil {
		log.Fatal(err)
	}

	// 自动迁移
	if err := db.AutoMigrate(&User{}, &Product{}); err != nil {
		log.Fatal(err)
	}

	// 创建仓库工厂
	factory := NewRepositoryFactory(db)
	ctx := context.Background()

	// 使用用户仓库
	userRepo := factory.UserRepository()

	// 1. 创建用户
	user := &User{
		Name:   "张三",
		Email:  "zhangsan@example.com",
		Age:    25,
		Active: true,
	}

	err = userRepo.Create(ctx, user)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("创建用户成功: %v\n", user.ID)

	// 2. 根据ID查找
	foundUser, err := userRepo.FindByID(ctx, user.ID)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("找到用户: %v\n", foundUser.Name)

	// 3. 更新用户
	foundUser.Age = 26
	err = userRepo.Update(ctx, foundUser)
	if err != nil {
		log.Fatal(err)
	}

	// 4. 条件查询
	users, err := userRepo.Find(ctx, "age > ?", 20)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("年龄大于20的用户数量: %d\n", len(users))

	// 5. 分页查询
	users, pageInfo, err := userRepo.Paginate(ctx, 1, 10, "active = ?", true)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("第1页，共%d条，总页数: %d\n", len(users), pageInfo.TotalPage)

	// 6. 使用选项查询
	options := &Options{
		Preloads: []string{},
		Selects:  []string{"id", "name", "email"},
		Order:    "created_at DESC",
		Limit:    5,
	}
	users, err = userRepo.FindWithOptions(ctx, nil, options)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("users: %v\n", users)

	// 7. 事务示例
	err = userRepo.WithTx(db.Begin()).Create(ctx, &User{
		Name:  "李四",
		Email: "lisi@example.com",
		Age:   30,
	})
	if err != nil {
		log.Fatal(err)
	}

	// 8. 使用泛型仓库
	productRepo := GetRepository[Product](db)
	product := &Product{
		Name:  "商品1",
		Price: 99.99,
		Stock: 100,
	}

	err = productRepo.Create(ctx, product)
	if err != nil {
		log.Fatal(err)
	}

	// 9. 统计数量
	count, err := productRepo.Count(ctx, "price > ?", 50)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("价格大于50的商品数量: %d\n", count)
}

func GetFreePort() (port int, err error) {
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
