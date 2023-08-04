package main

import (
	"context"
	"crypto/hmac"
	"crypto/sha1"
	"fmt"
	"math/rand"
	"net/url"
	"os"
	"reflect"
	"regexp"
	"strconv"
	"strings"
	"testing"
	"time"
	"unsafe"

	"github.com/bitly/go-simplejson"
	"github.com/lwenjim/testgo/foo"
	"gopkg.in/validator.v2"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/assert"

	_ "github.com/go-sql-driver/mysql"
)

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
	fmt.Println(123)
	s, err := miniredis.Run()
	assert.Nil(t, err)

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

func TestJson(t *testing.T) {
	js, _ := simplejson.NewJson([]byte("{\"authToken\":\"abc\"}"))
	fmt.Println(js.Get("authToken").String())
}

func TestPhoneEmail(t *testing.T) {
	emailAddress := "779772852@qq.com"
	pattern := `^(\w+([-+.]\w+)*@\w+([-.]\w+)*\.\w+([-.]\w+)*|1[345789]{1}\\d{9})$`
	reg := regexp.MustCompile(pattern)
	result := reg.MatchString(emailAddress)
	fmt.Printf("result: %v\n", result)
}
func TestValidate(t *testing.T) {
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

func TestGeneric(t *testing.T) {
	type Foo[T int | string] struct {
		Name T
		age  T
	}
	var f Foo[int]
	fmt.Printf("f: %v\n", f)
	fmt.Printf("f.age: %v\n", f.age)
	fmt.Printf("f.Name: %v\n", f.Name)
}

func TestSql(t *testing.T) {
	buff, err := os.ReadFile("data.txt")
	assert.Nil(t, err)
	for _, data := range strings.Split(string(buff), "\n") {
		data = strings.Trim(data, "\n\r\t")
		strs := strings.Split(data, "|")
		if len(strs) <= 1 {
			fmt.Println(data)
			continue
		}
		list := strings.Split(strs[4], "[")
		sql := list[0]
		for _, val := range strings.Split(strings.Trim(list[1], "]"), " ") {
			switch reflect.TypeOf(val).String() {
			case "string":
				sql = strings.Replace(sql, "?", "'"+val+"'", 1)
			case "uint32":
				sql = strings.Replace(sql, "?", val, 1)
			}
		}
		fmt.Println(sql)
	}
}

func TestSwith(t *testing.T) {
	i := time.Now().Unix()
	switch i % 2 {
	default:
		println(789)
	case 0:
		println(123)
		// case 1:
		// 	println(456)
	}
	println(i)
}

func TestPrivateField(t *testing.T) {
	p := foo.InitProgrammer()
	fmt.Println(p)
	lang := (*string)(unsafe.Pointer(uintptr(unsafe.Pointer(&p)) + unsafe.Sizeof(int(0))))
	*lang = "Golang"
	fmt.Println(p)

	T := foo.TestPointer{A: 1}
	pb := (*int)(unsafe.Pointer(uintptr(unsafe.Pointer(&T)) + 8))
	/*
	   Tmp := uintptr(unsafe.Pointer(&T)) + 8)
	   pb := (*int)(unsafe.Pointer(Tmp)
	   千万不能出现这种用临时变量中转一下的情况。因为GC可能因为优化内存碎片的原因移动了这个对象。只保留了指针的地址是没有意义的。
	*/
	*pb = 2

	c := (*string)(unsafe.Pointer(uintptr(unsafe.Pointer(&T)) + 8 + 8))
	*c = "abc"

	d := (*int)(unsafe.Pointer(uintptr(unsafe.Pointer(&T)) + unsafe.Sizeof(int(0)) + unsafe.Sizeof(int(0)) + unsafe.Sizeof(string(""))))
	*d = 4

	T.OouPut() //1 2

	fmt.Printf("unsafe.Sizeof(int(0)): %v\n", unsafe.Sizeof(string("")))

	fmt.Printf("unsafe.Alignof(p): %v\n", unsafe.Alignof(p))
}

func TestSh1(t *testing.T) {
	hs := hmac.New(sha1.New, []byte("abc"))
	if _, err := hs.Write([]byte("fasdfasdfasdfsfsdfasfdsdf")); err != nil {
		fmt.Printf("err: %v\n", err)
	}
	data := fmt.Sprintf("%x\n", hs.Sum(nil))
	fmt.Printf("data: %v\n", len(data))
}
