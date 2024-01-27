package main

import (
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gin-gonic/gin/binding"
	"github.com/go-playground/validator/v10"
)

// Booking 包含绑定和验证的数据。
type Booking struct {
	// CheckIn  time.Time `form:"check_in" binding:"" time_format:"2006-01-02"`
	// CheckOut time.Time `form:"check_out" binding:"gtfield=CheckIn" time_format:"2006-01-02"`
	// Name     string    `form:"name" binding:"required,maxStr=10"`
	Address Address `json:"address" binding:"required"`
}

type Address struct {
	Info string `json:"address" binding:"required,maxStr=1"`
}

func main() {
	route := gin.Default()
	if v, ok := binding.Validator.Engine().(*validator.Validate); ok {
		_ = v.RegisterValidation("bookabledate", func(fl validator.FieldLevel) bool {
			date, ok := fl.Field().Interface().(time.Time)
			if ok {
				return !time.Now().After(date)
			}
			return false
		})
	}
	if v, ok := binding.Validator.Engine().(*validator.Validate); ok {
		_ = v.RegisterValidation("maxStr", func(fl validator.FieldLevel) bool {
			want, err := strconv.ParseInt(fl.Param(), 10, 64)
			if err != nil {
				return false
			}
			got := int64(len([]rune(fl.Field().String())))
			return got <= want
		})
	}
	route.POST("/bookable", getBookable)
	_ = route.Run(":8085")
}

func getBookable(c *gin.Context) {
	var b Booking
	if err := c.ShouldBindJSON(&b); err == nil {
		c.JSON(http.StatusOK, gin.H{"message": "Booking dates are valid!"})
	} else {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
	}
}
