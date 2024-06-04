package main

import (
	"encoding/json"
	"fmt"
	"net/http"

	"github.com/gin-gonic/gin"
)

func main() {
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
