package main

import (
	"fmt"
	"time"

	"gorm.io/driver/mysql"
	"gorm.io/gorm"
)

func MonitorConnections(db *gorm.DB) {
	// 获取底层的 *sql.DB
	sqlDB, err := db.DB()
	if err != nil {
		panic(err)
	}

	// 定期获取连接池统计信息
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()

	for range ticker.C {
		stats := sqlDB.Stats()

		fmt.Printf("【连接池统计】%s\n", time.Now().Format("15:04:05"))
		fmt.Printf("├─ 最大打开连接数: %d\n", stats.MaxOpenConnections)
		fmt.Printf("├─ 已打开连接数: %d\n", stats.OpenConnections)
		fmt.Printf("├─ 使用中连接数: %d\n", stats.InUse)
		fmt.Printf("├─ 空闲连接数: %d\n", stats.Idle)
		fmt.Printf("├─ 等待新连接的次数: %d\n", stats.WaitCount)
		fmt.Printf("├─ 等待连接的总时间: %v\n", stats.WaitDuration)
		fmt.Printf("└─ 空闲连接关闭次数: %d\n", stats.MaxIdleClosed)

		// 计算使用率
		if stats.MaxOpenConnections > 0 {
			usage := float64(stats.InUse) / float64(stats.MaxOpenConnections) * 100
			fmt.Printf("📊 连接使用率: %.1f%%\n", usage)
		}

		fmt.Println()
	}
}

func main() {
	dsn := "root@tcp(127.0.0.1:3306)/test?charset=utf8mb4&parseTime=True&loc=Local"
	db, err := gorm.Open(mysql.Open(dsn), &gorm.Config{})
	if err != nil {
		panic(err)
	}

	// 配置连接池
	sqlDB, _ := db.DB()
	sqlDB.SetMaxOpenConns(100) // 最大连接数
	sqlDB.SetMaxIdleConns(20)  // 最大空闲连接数
	sqlDB.SetConnMaxLifetime(time.Hour)

	// 启动监控
	go MonitorConnections(db)

	// 你的业务逻辑...
	select {} // 保持程序运行
}
