package main

import (
	"cmp"
	"context"
	"crypto/hmac"
	"crypto/sha1"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"math"
	"math/rand"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"reflect"
	"regexp"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/bitly/go-simplejson"
	"github.com/google/go-querystring/query"
	"github.com/google/uuid"
	"golang.org/x/exp/slices"
	"golang.org/x/exp/slog"
	"gopkg.in/validator.v2"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/assert"

	_ "github.com/go-sql-driver/mysql"
)

type Animat[T int] struct {
	name T
}

func (a Animat[T]) Say() T {
	return a.name
}
func TestReplaceAll(t *testing.T) {
	bodyBuffer := `
	{
		"ret": 0,
		"msg": "",
		"is_lost":0,
		"nickname": "Liuli",
		"gender": "男",
		"gender_type": 2,
		"province": "广东",
		"city": "深圳",
		"year": "1990",
		"constellation": "",
		"figureurl": "http:\/\/qzapp.qlogo.cn\/qzapp\/1111401546\/CF6A45A094764AC2FBEC5D7966A27EDA\/30",
		"figureurl_1": "http:\/\/qzapp.qlogo.cn\/qzapp\/1111401546\/CF6A45A094764AC2FBEC5D7966A27EDA\/50",
		"figureurl_2": "http:\/\/qzapp.qlogo.cn\/qzapp\/1111401546\/CF6A45A094764AC2FBEC5D7966A27EDA\/100",
		"figureurl_qq_1": "http://thirdqq.qlogo.cn/g?b=oidb&k=dALcAodpne7ToSdfF91gdg&kti=ZNXUdAAAAAA&s=40&t=1448142454",
		"figureurl_qq_2": "http://thirdqq.qlogo.cn/g?b=oidb&k=dALcAodpne7ToSdfF91gdg&kti=ZNXUdAAAAAA&s=100&t=1448142454",
		"figureurl_qq": "http://thirdqq.qlogo.cn/g?b=oidb&k=dALcAodpne7ToSdfF91gdg&kti=ZNXUdAAAAAA&s=100&t=1448142454",
		"figureurl_type": "0",
		"is_yellow_vip": "0",
		"vip": "0",
		"yellow_vip_level": "0",
		"level": "0",
		"is_yellow_year_vip": "0"
	}	
	`
	data := regexp.MustCompile(`[\n\t]`).ReplaceAllString(bodyBuffer, "")
	fmt.Printf("data: %v\n", data)
}

func FancyHandleError(err error) (b bool) {
	if err != nil {
		// notice that we're using 1, so it will actually log the where
		// the error happened, 0 = this function, we don't want that.
		pc, fn, line, _ := runtime.Caller(1)

		//log.Printf("[error] in %s[%s:%d] %v", runtime.FuncForPC(pc).Name(), fn, line, err)
		fmt.Printf("[error] in %s[%s:%d] %v", runtime.FuncForPC(pc).Name(), fn, line, err)
		b = true
	}
	return
}

func TestErrorFormat(t *testing.T) {
	if FancyHandleError(fmt.Errorf("it's the end of the world\n")) {
		log.Print("stuff")
	}
}

func TestError(t *testing.T) {
	var BaseErr = errors.New("base error")
	err1 := fmt.Errorf("wrap base: %w", BaseErr)
	err2 := fmt.Errorf("wrap err1: %w", err1)
	println(err2 == BaseErr)

	if !errors.Is(err2, err1) {
		panic("err2 is not BaseErr")
	}
	println("err2 is BaseErr")
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

	str := " abc "
	str = strings.TrimSpace(str)
	fmt.Printf("str: 1111%v32222\n", str)
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

func TestSh1(t *testing.T) {
	hs := hmac.New(sha1.New, []byte("abc"))
	if _, err := hs.Write([]byte("fasdfasdfasdfsfsdfasfdsdf")); err != nil {
		fmt.Printf("err: %v\n", err)
	}
	data := fmt.Sprintf("%x\n", hs.Sum(nil))
	fmt.Printf("data: %v\n", len(data))
}

func TestStruct(t *testing.T) {
	type Woman struct {
		Name string
	}
	var w = Woman{"abc"}
	fmt.Printf("w.Name: %v\n", w.Name)
}

func TestSpace(t *testing.T) {
	data := `a
	
	b`
	re := regexp.MustCompile(`[\s\n\t]`)
	data = re.ReplaceAllString(data, "")
	fmt.Printf("data: %v\n", data)
}

func TestQueryString(t *testing.T) {
	type TokenRequest struct {
		GrantType    string `json:"grant_type" url:"grant_type"`
		ClientId     string `json:"client_id" url:"client_id"`
		ClientSecret string `json:"client_secret" url:"client_secret"`
		Code         string `json:"code" url:"code"`
		RedirectUri  string `json:"redirect_uri" url:"redirect_uri"`
		Fmt          string `json:"fmt" url:"fmt"`
		NeedOpenid   string `json:"need_openid" url:"need_openid"`
	}
	param := TokenRequest{
		GrantType:    "abc",
		ClientId:     "123",
		ClientSecret: "123",
		Code:         "fasdf",
		RedirectUri:  "fasdf",
		Fmt:          "fsd",
		NeedOpenid:   "fas  d",
	}
	values, err := query.Values(param)
	assert.Nil(t, err)
	fmt.Println(values.Encode())
}

func TestResult(t *testing.T) {
	type GetUserInfoResponse struct {
		Ret              int32  `json:"ret"`
		Msg              string `json:"msg"`
		NickName         string `json:"nickname"`
		Code             uint64 `json:"code"`
		Error            int    `json:"error"`
		ErrorDescription string `json:"error_description"`
	}
	data := `{"ret":-1,"msg":"client request's parameters are invalid, invalid openid"}`
	var v GetUserInfoResponse
	_ = json.Unmarshal([]byte(data), &v)
	fmt.Printf("v: %v\n", v)
}

func TestHour(t *testing.T) {
	// executeTime, err := time.Parse("2006-01-02 15:00:00", time.Now().Add(-time.Hour).Format("2006-01-02 15:00:00"))
	// assert.Nil(t, err)

	// fmt.Printf("executeTime.Unix(): %v\n", executeTime.Unix())

	layout := "2006-01-02 15:00:00"
	executeTime, _ := time.Parse(layout, time.Now().Format(layout))
	fmt.Printf("executeTime.Format(\"2006-01-02 15:04:05\"): %v\n", executeTime.Format("2006-01-02 15:04:05"))

	a := time.Now().AddDate(0, 0, -1)
	fmt.Printf("time.Now().After(a): %v\n", time.Now().After(a))
}

func TestSortSlice(t *testing.T) {
	people := []struct {
		Name string
		Age  int
	}{
		{"Gopher", 7},
		{"Alice", 55},
		{"Vera", 24},
		{"Bob", 75},
	}
	sort.Slice(people, func(i, j int) bool { return people[i].Name < people[j].Name })
	fmt.Println("By name:", people)

	sort.Slice(people, func(i, j int) bool { return people[i].Age < people[j].Age })
	fmt.Println("By age:", people)

	fmt.Println(float64(time.Now().Unix()) * math.Pow10(-10))
	fmt.Printf("rand.Float64(): %v\n", rand.Float64()*math.Pow10(5))

	fmt.Println(uint64(rand.Intn(20)))
}

func TestAirplaneGameSign(t *testing.T) {
	sha := sha256.New()
	_, err := fmt.Fprintf(sha, "%s:%d:%d", "3I2oPTZSg", 123, 100)
	assert.Nil(t, err)
	fmt.Printf("%x\n", sha.Sum(nil))

	data := float64(time.Now().Unix())*math.Pow10(-10) + 123
	fmt.Printf("data: %v\n", data)

	values := url.Values{}
	values.Add("api_key", "key_from_environment_or_flag/?")
	values.Add("another_thing", "foobar")
	query := values.Encode()
	fmt.Printf("query2: %v\n", query)

	sha = sha256.New()
	_, err = fmt.Fprintf(sha, "%v:%v:%v", "张三", "420704192001144673", "3I2oPTZSg")
	assert.Nil(t, err)
	fmt.Printf("%x\n", sha.Sum(nil))

	fmt.Printf("time.Now().Hour(): %v\n", time.Now().Hour())

	fmt.Printf("time.Now().Format(\"2006-01\"): %v\n", time.Now().Format("2006-01"))

	var a = 123
	func() {
		a = 456
	}()
	fmt.Printf("a: %v\n", a)
}

func TestClear(t *testing.T) {
	m := map[int]int{1: 1, 2: 2, 3: 3, 4: 4, 5: 5}
	fmt.Println(len(m)) // 5
	clear(m)
	fmt.Println(len(m)) // 0

	s := make([]int, 0, 100) // 故意给个大的cap便于观察
	s = append(s, []int{1, 2, 3, 4, 5}...)
	fmt.Println(s)              // [1 2 3 4 5]
	fmt.Println(len(s), cap(s)) // len: 5; cap: 100
	clear(s)
	fmt.Println(s)              // [0 0 0 0 0]
	fmt.Println(len(s), cap(s)) // len: 5; cap: 100

	fmt.Println(runtime.Version())
	defer func() {
		a := recover()
		fmt.Printf("a: %v\n", a)
	}()
	panic(nil)
}

func TestLog(t *testing.T) {
	_logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	_logger.Info("hello", "count", 3)
}

func TestSlices(t *testing.T) {
	i, ok := slices.BinarySearch([]string{"a", "c", "d"}, "c")
	assert.True(t, ok)
	fmt.Printf("i: %v\n", i)

	type Person struct {
		Name string
		Age  int
	}
	people := []Person{
		{"Alice", 55},
		{"Bob", 24},
		{"Gopher", 13},
	}
	n, found := slices.BinarySearchFunc(people, Person{"Bob", 0}, func(a, b Person) int {
		return cmp.Compare(a.Name, b.Name)
	})
	fmt.Println("Bob:", n, found) // Bob: 1 true

	names := make([]string, 2, 5)
	names = slices.Clip(names)
	fmt.Printf("长度：%d,容量：%d\n", len(names), cap(names))
	// 长度：2,容量：2

	names = []string{"路多辛的博客", "路多辛的所思所想"}
	namesCopy := slices.Clone(names)

	fmt.Println(namesCopy)

	var a Animat[int]
	a.name = 123
	fmt.Println(a.Say())

	// slices.Compact
	seq := []int{0, 1, 1, 2, 5, 5, 5, 8}
	seq = slices.Compact(seq)
	fmt.Println(seq) // [0 1 2 5 8]

	// 冒泡排序 它重复地走访要排序的数列，一次比较两个数据元素，如果顺序不对则进行交换，并一直重复这样的走访操作，直到没有要交换的数据元素为止。
	//arr := []int{6, 5, 4, 3, 2, 1}
	arr := []int{1, 6, 5, 4, 3, 2}
	count := len(arr)
	cnt := 0
	for i := 0; i < count; i++ {
		for j := i + 1; j < count; j++ {
			if arr[i] > arr[j] {
				arr[i], arr[j] = arr[j], arr[i]
				cnt++
			}
		}
	}
	fmt.Printf("排序后的数组 arr: %v\n", arr)
	fmt.Printf("交换次数: %+v\n", cnt)

}

func TestEscapes(t *testing.T) {
	a := []int{}
	b := []int{1}
	c := 1

	fmt.Printf("a: %v\n", a)
	fmt.Printf("b: %v\n", b)
	fmt.Printf("c: %v\n", c)

	//	420704 19900113 467X
	data := "42070419900113467X"
	birth := data[6:10]
	year, _ := strconv.Atoi(birth)
	fmt.Printf("birth: %#v\n", time.Now().Year()-year)
}

func TestStreamer(t *testing.T) {
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, err := w.Write([]byte(`123`))
		assert.Nil(t, err)
	}))
	resp, err := http.Get(ts.URL)
	assert.Nil(t, err)
	defer resp.Body.Close()
	buffer, err := io.ReadAll(resp.Body)
	assert.Nil(t, err)
	fmt.Println(string(buffer))

	file, err := os.Create("a.log")
	assert.Nil(t, err)
	i, err := file.WriteString("hello world")
	assert.Nil(t, err)
	fmt.Printf("i: %v\n", i)

	err = os.Mkdir("abc", os.ModeDir)
	assert.Nil(t, err)
	if err == nil {
		os.Remove("abc")
	}
}

func TestRegexp(t *testing.T) {
	rest := regexp.MustCompile("^[0-9]{6}$").MatchString("123123")
	fmt.Printf("rest: %v\n", rest)
}

type TypicalErr struct {
	e string
}

func (t TypicalErr) Error() string {
	return t.e
}
func TestErrorIs(t *testing.T) {
	// 判断被包装过的error是否包含指定错误
	var BaseErr = errors.New("base error")
	err1 := fmt.Errorf("wrap base: %w", BaseErr)
	err2 := fmt.Errorf("wrap err1: %w", err1)
	println(err2 == BaseErr)
	if !errors.Is(err2, BaseErr) {
		panic("err2 is not BaseErr")
	}
	println("err2 is BaseErr")

	// 判断被包装过的error是否为指定类型
	err := TypicalErr{"typical error"}
	err1 = fmt.Errorf("wrap err: %w", err)
	err2 = fmt.Errorf("wrap err1: %w", err1)
	var e TypicalErr
	if !errors.As(err2, &e) {
		panic("TypicalErr is not on the chain of err2")
	}
	println("TypicalErr is on the chain of err2")
	println(err == e)

}

// 测试上下文
const (
	KEY = "trace_id"
)

func NewRequestID() string {
	return strings.Replace(uuid.New().String(), "-", "", -1)
}

func NewContextWithTraceID() context.Context {
	ctx := context.WithValue(context.Background(), KEY, NewRequestID())
	return ctx
}

func PrintLog(ctx context.Context, message string) {
	fmt.Printf("%s|info|trace_id=%s|%s", time.Now().Format("2006-01-02 15:04:05"), GetContextValue(ctx, KEY), message)
}

func GetContextValue(ctx context.Context, k string) string {
	v, ok := ctx.Value(k).(string)
	if !ok {
		return ""
	}
	return v
}

func ProcessEnter(ctx context.Context) {
	PrintLog(ctx, "Golang梦工厂")
}
func TestContext(t *testing.T) {
	// context可以用来在goroutine之间传递上下文信息
	// 作用就是在不同的goroutine之间同步请求特定的数据、取消信号以及处理请求的截止日期
	ProcessEnter(NewContextWithTraceID())
}

func NewContextWithTimeout() (context.Context, context.CancelFunc) {
	return context.WithTimeout(context.Background(), 3*time.Second)
}

func HttpHandler() {
	ctx, cancel := NewContextWithTimeout()
	defer cancel()
	deal(ctx)
}

func deal(ctx context.Context) {
	for i := 0; i < 10; i++ {
		time.Sleep(1 * time.Second)
		select {
		case <-ctx.Done():
			fmt.Println(ctx.Err())
			return
		default:
			fmt.Printf("deal time is %d\n", i)
		}
	}
}

func TestContextTimeout(t *testing.T) {
	// 在多个 Goroutine 组成的树中同步取消信号以减少对资源的消耗和占用

	HttpHandler()
}

func TestChannel(t *testing.T) {
	ch := make(chan struct{}, 1)
	go func() {
		fmt.Println("start working")
		time.Sleep(time.Second * 1)
		ch <- struct{}{}
	}()
	<-ch
	fmt.Println("finished")
}

func TestSlice(t *testing.T) {
	s := new([]int)
	fmt.Printf("s: %v\n", s)
	s2 := make([]int, 1)
	fmt.Println(s2)
}
