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
	"github.com/golang-jwt/jwt"
	"github.com/google/go-querystring/query"
	"github.com/google/uuid"
	"github.com/lianggaoqiang/progress"
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

	fmt.Printf("%s\n", strings.Repeat("=", 100))
	sli := []int{}
	fmt.Printf("%p, %d\n", sli, cap(sli))
	sli = append(sli, 1)
	fmt.Printf("%p, %d\n", sli, cap(sli))
	sli = append(sli, 1)
	fmt.Printf("%p, %d\n", sli, cap(sli))

	sli2 := make([]int, 100)
	fmt.Printf("%p, %d\n", sli2, cap(sli2))
	sli2 = append(sli2, 1)
	fmt.Printf("%p, %d\n", sli2, cap(sli2))

	sli3 := []int{1}
	sli4 := append([]int{}, sli3...)
	fmt.Printf("%p, %d, %v\n", sli4, cap(sli4), sli4)
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
type WithValueType string

const (
	KEY WithValueType = "trace_id"
)

func NewRequestID() WithValueType {
	return WithValueType(strings.Replace(uuid.New().String(), "-", "", -1))
}

func NewContextWithTraceID() context.Context {
	ctx := context.WithValue(context.Background(), KEY, NewRequestID())
	return ctx
}

func PrintLog(ctx context.Context, message string) {
	fmt.Printf("%s|info|trace_id=%s|%s", time.Now().Format("2006-01-02 15:04:05"), GetContextValue(ctx, string(KEY)), message)
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

func TestT1(t *testing.T) {
	a := firstMissingPositive([]int{1, 5, 1, 90, 40})
	fmt.Printf("a: %v\n", a)
}

func firstMissingPositive(A []int) int {
	length := len(A)
	for i := 0; i < length; {
		if A[i] > 0 && A[i] <= length && A[i] != A[A[i]-1] {
			A[i], A[A[i]-1] = A[A[i]-1], A[i]
		} else {
			i++
		}
	}
	for i := 0; i < length; i++ {
		if A[i] != i+1 {
			return i + 1
		}
	}
	return length + 1
}

type Node struct {
	Val   int   `json:"val,omitempty"`
	Left  *Node `json:"left,omitempty"`
	Right *Node `json:"right,omitempty"`
	Next  *Node `json:"next,omitempty"`
}

func TestBinarySearchForNode(t *testing.T) {
	node7 := Node{
		Val:   7,
		Left:  nil,
		Right: nil,
		Next:  nil,
	}
	node5 := Node{
		Val:   5,
		Left:  nil,
		Right: nil,
		Next:  nil,
	}
	node4 := Node{
		Val:   4,
		Left:  nil,
		Right: nil,
		Next:  nil,
	}
	node3 := Node{
		Val:   3,
		Left:  nil,
		Right: nil,
		Next:  nil,
	}
	node2 := Node{
		Val:   2,
		Left:  nil,
		Right: nil,
		Next:  nil,
	}
	node1 := Node{
		Val:   1,
		Left:  nil,
		Right: nil,
		Next:  nil,
	}
	node1.Left = &node2
	node1.Right = &node3

	node2.Left = &node4
	node2.Right = &node5

	node3.Right = &node7

	nodeFormat(&node1)
	buffer, err := json.Marshal(node1)
	assert.Nil(t, err)
	fmt.Printf("data: %s\n", string(buffer))
}

func nodeFormat(root *Node) {
	var handle func(*Node, int)
	list := make(map[int][]*Node)
	handle = func(node *Node, depth int) {
		if node == nil {
			return
		}
		list[depth] = append(list[depth], node)
		handle(node.Left, depth+1)
		handle(node.Right, depth+1)
	}
	handle(root, 0)
	for i := 0; i < len(list); i++ {
		if len(list[i]) > 1 {
			for j := 0; j < len(list[i])-1; j++ {
				list[i][j].Next = list[i][j+1]
			}
		}
	}
}

func TestBinarySearchForArr(t *testing.T) {
	arr := []int{0, 1, 2, 3, 4, 5, 6, 7, 8, 9}
	res := arrFormat(arr)
	fmt.Printf("res: %v\n", res)
}

/**
* [1] len=1
* 1:2, 2:
* [1, 2] len=2
* 1:len=2, :
* [1, 2, 3] len=3
* 1:len-1=2, len-1:
* [1, 2, 3, 4] len=4
* 1:len-1=3, len-1:
* [1, 2, 3, 4, 5] len=5
* 1:len-2=3, len-2:
* [1, 2, 3, 4, 5, 6] len=6
* 1:len-2=4, len-2:
* [1, 2, 3, 4, 5, 6, 7] len=7
* 1:len-3=4, len-3:
* 1=2^0
* 2=2^1
* 4=2^2
* 8=2^3
 */
func arrFormat(arr []int) []string {
	for i := 0; i < len(arr)-1; i++ {
		for j := i + 1; j < len(arr); j++ {
			if arr[j] < arr[i] {
				arr[j], arr[i] = arr[i], arr[j]
			}
		}
	}
	var handle func([]int, int)
	list := make(map[int][]int)
	handle = func(arr []int, depth int) {
		if len(arr) == 0 {
			return
		}
		middle := arr[0]
		var left, right []int
		length := len(arr)
		left = arr[1 : length/2+1]
		right = arr[length/2+1:]
		list[depth] = append(list[depth], middle)
		handle(left, depth+1)
		handle(right, depth+1)
	}
	handle(arr, 0)
	var res []string
	for i := 0; i < len(list); i++ {
		for j := 0; j < len(list[i]); j++ {
			res = append(res, fmt.Sprintf("%d", list[i][j]))
		}
		res = append(res, "#")
	}
	return res
}

/*
*

// 3 ^ 1
// 00000011
// 00000001
// 00000010

// 2 ^ 1
// 00000010
// 00000001
// 00000011

// 2 ^ 3
// 00000010
// 00000011
// 00000001
*/
func TestXOR(t *testing.T) {
	var arr = []int{3, 10, 5, 25, 2, 8}
	var x, y int
	x = 0
	y = 1
	for i := 0; i < len(arr)-1; i++ {
		for j := i; j < len(arr); j++ {
			if arr[x]^arr[y] < arr[i]^arr[j] {
				x = i
				y = j
			}
		}
	}
	fmt.Printf("x: %d, y: %d\n", arr[x], arr[y])
}

func TestNil(t *testing.T) {
	m := make(map[int]int)
	fmt.Printf("m: %v\n", m)
}

func TestMap(t *testing.T) {
	fmt.Printf("time.Now().UnixMicro(): %v\n", time.Now().UnixMicro())
	m := make(map[int]int)
	fmt.Printf("m: %p\n", m)
	fmt.Printf("&m: %p\n", &m)

	s := make([]int, 0)
	fmt.Printf("s: %p\n", s)
	fmt.Printf("&s: %p\n", &s)

	c := make(chan int)
	fmt.Printf("c: %p\n", c)
	fmt.Printf("&c: %p\n", &c)
}

func TestOperator(t *testing.T) {
	a := 2
	b := 10
	// 00000010
	// 00001010
	// 00001010
	fmt.Printf("a=%b, b=%b, a&b=%b\n", a, b, a&b)

	// 00000010
	// 00001010
	// 00001010
	fmt.Printf("a=%b, b=%b, a|b=%b\n", a, b, a|b)

	// 00000010
	// 00001010
	// 00001000
	fmt.Printf("a=%b, b=%b, a^b=%b\n", a, b, a^b)

	// 00000010 00000010
	// 00001010 11110101
	// 00001000 00000000
	fmt.Printf("a=%b, b=%b, a&^b=%b\n", a, b, a&^b)

	// 00000010 00000100 <<1
	fmt.Printf("a=%b, (a<<1)=%b\n", a, a<<1)

	// 00000010 00000100 >1
	fmt.Printf("a=%b, (a>>1)=%b\n", a, a>>1)

	fmt.Printf("time.Now().Format(\"20060102\"): %v\n", time.Now().Format("20060102"))

	fmt.Printf("%T\n", 'b'-'a')

	fmt.Printf("%v\n", reflect.TypeOf('b'-'a'))
	// 64+8+2/8 => 74/8=>1001 => 74/8 = 9_2
}

func TestStruct2(t *testing.T) {
	a := &struct{}{}
	fmt.Printf("%p\n", a)

	b := &struct{}{}
	fmt.Printf("%p\n", b)
}

func TestRepeatDNA(t *testing.T) {
	// 第一块循环
	// 65 65 65 65 65 67 67 67 67 67 65 65 65 65 65 67 67 67 67 67 67 65 65 65 65 65 71 71 71 84 84 84
	// 65 65 65 65 65 67 67 67 67 67

	// 65 65 65 65 65 67 67 67 67 67 65 65 65 65 65 67 67 67 67 67 67 65 65 65 65 65 71 71 71 84 84 84
	// 	  65 65 65 65 65 67 67 67 67 67

	// 65 65 65 65 65 67 67 67 67 67 65 65 65 65 65 67 67 67 67 67 67 65 65 65 65 65 71 71 71 84 84 84
	// 	     65 65 65 65 65 67 67 67 67 67

	// 65 65 65 65 65 67 67 67 67 67 65 65 65 65 65 67 67 67 67 67 67 65 65 65 65 65 71 71 71 84 84 84
	// 	        65 65 65 65 65 67 67 67 67 67

	// ...
	// 65 65 65 65 65 67 67 67 67 67 65 65 65 65 65 67 67 67 67 67 67 65 65 65 65 65 71 71 71 84 84 84
	// 	        														 65 65 65 65 65 67 67 67 67 67

	// 第二块循环
	// 65 65 65 65 65 67 67 67 67 67 65 65 65 65 65 67 67 67 67 67 67 65 65 65 65 65 71 71 71 84 84 84
	// 65 65 65 65 67 67 67 67 67 65

	// 65 65 65 65 65 67 67 67 67 67 65 65 65 65 65 67 67 67 67 67 67 65 65 65 65 65 71 71 71 84 84 84
	// 	  65 65 65 65 67 67 67 67 67 65

	// 65 65 65 65 65 67 67 67 67 67 65 65 65 65 65 67 67 67 67 67 67 65 65 65 65 65 71 71 71 84 84 84
	// 	     65 65 65 65 67 67 67 67 67 65

	// 65 65 65 65 65 67 67 67 67 67 65 65 65 65 65 67 67 67 67 67 67 65 65 65 65 65 71 71 71 84 84 84
	// 	        65 65 65 65 67 67 67 67 67 65

	// ...
	// 65 65 65 65 65 67 67 67 67 67 65 65 65 65 65 67 67 67 67 67 67 65 65 65 65 65 71 71 71 84 84 84
	// 	        														 65 65 65 65 67 67 67 67 67 65

	// 最后一块循环
	// 65 65 65 65 65 67 67 67 67 67 65 65 65 65 65 67 67 67 67 67 67 65 65 65 65 65 71 71 71 84 84 84
	// 65 65 65 65 71 71 71 84 84 84

	// 65 65 65 65 65 67 67 67 67 67 65 65 65 65 65 67 67 67 67 67 67 65 65 65 65 65 71 71 71 84 84 84
	// 	  65 65 65 65 71 71 71 84 84 84

	// 65 65 65 65 65 67 67 67 67 67 65 65 65 65 65 67 67 67 67 67 67 65 65 65 65 65 71 71 71 84 84 84
	// 	     65 65 65 65 71 71 71 84 84 84

	// 65 65 65 65 65 67 67 67 67 67 65 65 65 65 65 67 67 67 67 67 67 65 65 65 65 65 71 71 71 84 84 84
	// 	        65 65 65 65 71 71 71 84 84 84

	// ...

	//																	 start=len(arr)-1-9			end=len(arr)-1
	// 65 65 65 65 65 67 67 67 67 67 65 65 65 65 65 67 67 67 67 67 67 65 65 65 65 65 71 71 71 84 84 84
	// 	        														 65 65 65 65 71 71 71 84 84 84

	// 第二种方案
	// 65 65 65 65 65 67 67 67 67 67 65 65 65 65 65 67 67 67 67 67 67 65 65 65 65 65 71 71 71 84 84 84
	// 65 65 65 65 65 67 67 67 67 67

	// 65 65 65 65 65 67 67 67 67 67 65 65 65 65 65 67 67 67 67 67 67 65 65 65 65 65 71 71 71 84 84 84
	// 	  65 65 65 65 65 67 67 67 67 67

	// 65 65 65 65 65 67 67 67 67 67 65 65 65 65 65 67 67 67 67 67 67 65 65 65 65 65 71 71 71 84 84 84
	// 	  	 65 65 65 65 65 67 67 67 67 67

	// ...

	// 65 65 65 65 65 67 67 67 67 67 65 65 65 65 65 67 67 67 67 67 67 65 65 65 65 65 71 71 71 84 84 84
	// 	  	 															 65 65 65 65 65 67 67 67 67 67

	// s := "AAAAACCCCCAAAAACCCCCCAAAAAGGGTTT"
	// box := make(map[string]int)
	// var ret []string
	// for i := 0; i < len(s)-1-9+1; i++ {
	// 	for j := 0; j < len(s)-1-9+1; j++ {
	// 		if i == j {
	// 			continue
	// 		}
	// 		equal := true
	// 		for x := 0; x < 10; x++ {
	// 			if s[i+x] != s[j+x] {
	// 				equal = false
	// 				break
	// 			}
	// 		}
	// 		if equal {
	// 			key := s[i : i+10]
	// 			if _, ok := box[key]; !ok {
	// 				box[key] = 1
	// 			} else {
	// 				if box[key] == 2 {
	// 					ret = append(ret, key)
	// 				}
	// 				box[key] += 1
	// 			}
	// 		}
	// 	}
	// }

	// s := "AAAAACCCCCAAAAACCCCCCAAAAAGGGTTT"
	// box := make(map[string]int)
	// var ret []string
	// for i := 0; i < len(s)-1-9+1; i++ {
	// 	for j := 0; j < len(s)-1-9+1; j++ {
	// 		if i == j {
	// 			continue
	// 		}
	// 		if s[i:i+10] == s[j:j+10] {
	// 			key := s[i : i+10]
	// 			if _, ok := box[key]; !ok {
	// 				box[key] = 1
	// 			} else {
	// 				if box[key] == 1 {
	// 					ret = append(ret, key)
	// 				}
	// 				box[key] += 1
	// 			}
	// 		}
	// 	}
	// }
	// fmt.Printf("ret: %+v\n", ret)

	s := "AAAAACCCCCAAAAACCCCCCAAAAAGGGTTT"
	box := make(map[string]int)
	var ret []string
	for i := 0; i < len(s)-1-9+1; i++ {
		key := s[i : i+10]
		if _, ok := box[key]; !ok {
			box[key] = 1
		} else {
			if box[key] == 1 {
				ret = append(ret, key)
			}
			box[key] += 1
		}
	}
	fmt.Printf("ret: %+v\n", ret)
}

func TestMaxWordLengthMulti(t *testing.T) {
	// 给你一个字符串数组 words ，找出并返回 length(words[i]) * length(words[j]) 的最大值，并且这两个单词不含有公共字母。如果不存在这样的两个单词，返回 0
	// words := []string{"a", "ab", "abc", "d", "cd", "bcd", "abcd"}
	// words := []string{"cdbbfebebafbefc", "ecbeaeddcce", "aefeeddafccaedafddd", "cbe", "ececca", "adcfdbdffcebfedadcb", "edbfadcecbebfee", "eabcb", "bdfedaedbaeacf", "faabafbbbefdea", "deccfdffacbebdefbfa", "ffdf", "fdbeabbec", "cbcfeedaf", "ecdbfdebbebffbbbb", "ebee", "cfcdcbcfdacbdaaebfef", "dafabedfa", "babbdfcc", "eadeafdbcdbbaefbbbbdc", "faabad", "eeeaecdbbacbedbaeabd", "acfa", "eaaafeb", "acef", "dccaccfffedaabefccead", "bacdbfe", "fdfdafaa", "bacecdff", "cfadccadfdabbdcdaec", "acbdfffdbcdfffbdbec", "afbcfefc", "facaacffccecfff", "af", "aedcddabdddfdeafabfd", "fafbfeacffbbbceebaedc", "aabbbabddcadadda", "eccca", "fcafbdfb", "ffdadaeaebedec", "ccfc", "efaed", "eebbb", "dcafccfbbdfbddcfbefb", "aaeeb", "fcdd", "ccccb", "ddebebfdcdbaaf", "beeeb", "edbfdabdcfb", "cacfbf", "bceacbdababbfca", "ffb", "fcba", "bdfedbaafebbffcefece", "bf", "dbfbeabcecffdbcc", "dccebefccbecf", "aaebfacdaaabfbcfacd", "cb", "edbbbfcdbefeabcfd", "daabdcbadccfeffafa", "cfafbcdfbdabfadddddff", "cbfd", "bcaa", "dffbfebffedc", "ebcbfbaeadbbdfcaa", "dcedebbcdfffabbac", "dbedacddcec", "badedda", "beeeaaffcdadbdecaddc", "dcdbcdbffeddcfea", "dedbdecbca", "cbecacdcfcdcfbfeebdda", "bebbacebbfacfbbbed", "dc", "cdddaedbfeaeebdbef", "accbbd", "bbafead", "dcfba", "efac", "ffce", "cfa", "bac", "bdfdfecccfeadeafedee", "eedddbefdaefbcbf", "acedbeadaedfcdffebea", "cc", "cffbeebdedfdbf", "fdeacddefadbdecbe", "ccccedafdbedaeeb", "cfafddadadcfdbdfb", "aadbbedecd", "cadeffaaffdcaeeefdfbf", "adcaaefbffdfaadedbbb", "cbeebfeeddcfd", "abfaaecdffbdfafe", "fccbbae", "cefdee", "cfdbfbabacafecc"}
	var maxProduct func(words []string) int
	tmp, _ := os.ReadFile("a.log")
	var words []string
	_ = json.Unmarshal(tmp, &words)
	// keys := make([]string, 0)
	// values := make([]int, 0)
	// for i := 0; i < len(words); i++ {
	// 	for j := 0; j < len(words); j++ {
	// 		if i == j {
	// 			continue
	// 		}
	// 		key := fmt.Sprintf("%s|%s", words[i], words[j])
	// 		mul := len(words[i]) * len(words[j])
	// 		keys = append(keys, key)
	// 		values = append(values, mul)
	// 	}
	// }
	// partition := func(values []int, keys []string, left int, right int) int {
	// 	pivot := left
	// 	index := pivot + 1
	// 	for i := index; i <= right; i++ {
	// 		if values[i] < values[pivot] {
	// 			values[index], values[i] = values[i], values[index]
	// 			keys[index], keys[i] = keys[i], keys[index]
	// 			index++
	// 		}
	// 	}
	// 	if pivot != index-1 {
	// 		values[pivot], values[index-1] = values[index-1], values[pivot]
	// 		keys[pivot], keys[index-1] = keys[index-1], keys[pivot]
	// 	}
	// 	return index - 1
	// }
	// partitionIndex := 0
	// var quickSort func(arr []int, slave []string, left int, right int)
	// quickSort = func(values []int, keys []string, left int, right int) {
	// 	if left < right {
	// 		partitionIndex = partition(values, keys, left, right)
	// 		quickSort(values, keys, left, partitionIndex-1)
	// 		quickSort(values, keys, partitionIndex+1, right)
	// 	}
	// }
	// quickSort(values, keys, 0, len(keys)-1)
	// for x := len(values) - 1; x >= 0; x-- {
	// 	key := keys[x]
	// 	m := make(map[byte]int, 0)
	// 	isSame := false
	// 	isMiddlePassed := false
	// 	for i := 0; i < len(key); i++ {
	// 		if key[i] == '|' {
	// 			isMiddlePassed = true
	// 		}
	// 		if isMiddlePassed {
	// 			if _, ok := m[key[i]]; ok {
	// 				isSame = true
	// 				break
	// 			}
	// 		} else {
	// 			m[key[i]] = 1
	// 		}
	// 	}
	// 	if !isSame {
	// 		fmt.Printf("values[index]: %v\n", values[x])
	// 		fmt.Printf("key: %v\n", key)
	// 		break
	// 	}
	// }

	maxProduct = func(words []string) int {
		boxLen := len(words)
		ans := 0
		m := make(map[string]int)
		for i := 0; i < boxLen; i++ {
			l := 0
			for j := 0; j < len(words[i]); j++ {
				l |= 1 << (words[i][j] - 'a')
			}
			m[words[i]] = l
		}
		for i := 0; i < boxLen; i++ {
			for j := i + 1; j < boxLen; j++ {
				if m[words[i]]&m[words[j]] == 0 {
					ans = max(ans, len(words[i])*len(words[j]))
				}
			}
		}
		return ans
	}

	// func maxProduct(words []string) int {
	// 	x := 0
	// 	y := 0
	// 	boxLen := len(words)
	// 	for i := 0; i < boxLen-1; i++ {
	// 		m := make(map[byte]int)
	// 		for j := 0; j < len(words[i]); j++ {
	// 			if len(m) >= 26 {
	// 				break
	// 			}
	// 			if _, ok := m[words[i][j]]; ok {
	// 				continue
	// 			}
	// 			m[words[i][j]] = 1
	// 		}
	// 		for j := i + 1; j < boxLen; j++ {
	// 			if i == j {
	// 				continue
	// 			}
	// 			if x == i && y == j {
	// 				continue
	// 			}

	// 			isExists := false
	// 			n := make(map[byte]int)
	// 			for z := 0; z < len(words[j]); z++ {
	// 				if len(n) >= 26 {
	// 					break
	// 				}
	// 				if _, ok := m[words[j][z]]; ok {
	// 					isExists = true
	// 					break
	// 				}
	// 				n[words[j][z]] = 1
	// 			}

	//				if isExists {
	//					continue
	//				}
	//				if x == 0 && y == 0 {
	//					x = i
	//					y = j
	//				}
	//				if len(words[i])*len(words[j]) <= len(words[x])*len(words[y]) {
	//					continue
	//				}
	//				x = i
	//				y = j
	//			}
	//		}
	//		fmt.Printf("x: %d\n", x)
	//		fmt.Printf("y: %d\n", y)
	//		fmt.Printf("max: %d, len: %d\n", len(words[x])*len(words[y]), len(words))
	//		if x == y {
	//			return 0
	//		}
	//		return len(words[x]) * len(words[y])
	//	}

	ant := maxProduct(words)
	fmt.Printf("ant: %v\n", ant)
}

func TestCountYuanyinSub(t *testing.T) {
	vowelStrings := func(words []string, left int, right int) int {
		keys := 1
		keys |= 1 << ('e' - 'a')
		keys |= 1 << ('i' - 'a')
		keys |= 1 << ('o' - 'a')
		keys |= 1 << ('u' - 'a')
		cnt := 0
		for i := left; i <= right; i++ {
			last := len(words[i]) - 1
			if 1<<(words[i][0]-'a')&keys != 0 && 1<<(words[i][last]-'a')&keys != 0 {
				cnt++
			}
		}
		return cnt
	}
	var words = []string{"are", "amy", "u"}
	cnt := vowelStrings(words, 0, 2)
	fmt.Printf("cnt: %v\n", cnt)
}

func TestFindTheLongestBalancedSubstring(t *testing.T) {
	findTheLongestBalancedSubstring := func(s string) int {
		// n := len(s)
		// zero := 0
		// one := 0
		// ans := 0
		// for i := 0; i < n; i++ {
		// 	if s[i] == '0' {
		// 		if i > 0 && s[i-1] == '1' {
		// 			// nolint
		// 			ans = max(min(zero, one), ans)
		// 			one = 0
		// 			ans = 0
		// 		}
		// 		zero++
		// 	} else {
		// 		one++
		// 	}
		// }
		// ans = max(min(zero, one), ans)
		// return ans * 2

		// ans := 0
		// n := len(s)
		// for i := 0; i < n; {
		// 	zero := 0
		// 	one := 0
		// 	for i < n && s[i] == '0' {
		// 		i++
		// 		zero++
		// 	}
		// 	for i < n && s[i] == '1' {
		// 		i++
		// 		one++
		// 	}
		// 	ans = max(ans, min(zero, one))
		// }
		// return ans * 2

		// ans := 0
		// n := len(s)
		// expand := func(s string, x int, y int) int {
		// 	for x >= 0 && y <= n-1 && s[x] == '0' && s[y] == '1' {
		// 		x = x - 1
		// 		y = y + 1
		// 	}
		// 	return y - x - 1
		// }
		// for i := 0; i < n-1; i++ {
		// 	if s[i] == '0' && s[i+1] == '1' {
		// 		ans = max(ans, expand(s, i, i+1))
		// 	}
		// }
		// return ans

		ans := 0
		pre := 0
		cur := 0
		n := len(s)
		for i := 0; i < n; i++ {
			cur++
			if i == n-1 || s[i] != s[i+1] {
				if s[i] == '1' {
					ans = max(ans, min(pre, cur)*2)
				}
				pre = cur
				cur = 0
			}
		}
		return ans
	}
	s := "01000111"
	ret := findTheLongestBalancedSubstring(s)
	fmt.Printf("ret: %v\n", ret)
}

func TestBar(t *testing.T) {
	b := NewBar(0, 1000)
	for i := 0; i < 1000; i++ {
		b.Add(1)
		time.Sleep(time.Millisecond * 10)
	}
	p := progress.Start()

	// create a custom bar
	b1 := progress.NewBar().Custom(progress.BarSetting{
		Total:           50,
		StartText:       "[",
		EndText:         "]",
		PassedText:      "-",
		FirstPassedText: ">",
		NotPassedText:   "=",
	})

	// create a custom inline bar
	b2 := progress.NewBar().Custom(progress.BarSetting{
		UseFloat:        true,
		Inline:          true,
		StartText:       "|",
		EndText:         "|",
		FirstPassedText: ">",
		PassedText:      "=",
		NotPassedText:   " ",
	})

	// create a custom bar with emoji character
	b3 := progress.NewBar().Custom(progress.BarSetting{
		LeftSpace:     10,
		Total:         10,
		StartText:     "|",
		EndText:       "|",
		PassedText:    "⚡",
		NotPassedText: "  ",
	})

	// add bars in progress
	p.AddBar(b2)
	p.AddBar(b3)
	p.AddBar(b1)

	for i := 0; i <= 100; i++ {
		_ = b1.Inc()
		_ = b2.Add(1.4)
		_ = b3.Percent(float64(i))
		time.Sleep(time.Millisecond * 40)
	}
}

type MyClaims struct {
	Name string
}

func (*MyClaims) Valid() error {
	return nil
}
func TestEmpty(t *testing.T) {
	// num, err := phonenumbers.Parse("6502530000", "US")
	// assert.Nil(t, err)
	// fmt.Printf("num: %v\n", num)

	// formattedNum := phonenumbers.Format(num, phonenumbers.NATIONAL)
	// fmt.Printf("formattedNum: %v\n", formattedNum)

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"foo": "bar",
		"nbf": time.Date(2015, 10, 10, 12, 0, 0, 0, time.UTC).Unix(),
	})
	hmacSampleSecret := []byte("abc")

	tokenString, err := token.SignedString(hmacSampleSecret)
	assert.Nil(t, err)

	token, err = jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("Unexpected signing method: %v", token.Header["alg"])
		}
		return hmacSampleSecret, nil
	})
	if err != nil {
		log.Fatal(err)
	}

	if claims, ok := token.Claims.(jwt.MapClaims); ok {
		fmt.Println(claims["foo"], claims["nbf"])
	} else {
		fmt.Println(err)
	}

	m := map[int]string{
		1: "abc",
	}
	fmt.Printf("m[1]: %v\n", m[1])

	// var a interface{}
	// a = 123
	// if b, ok := a.(int32); ok {
	// 	fmt.Println("ok")
	// } else {
	// 	fmt.Printf("b: %v\n", b)
	// }

	// var m map[int]int
	// fmt.Printf("m: %p\n", m)
	// var s []int
	// fmt.Printf("s: %p\n", s)
	// var c chan int
	// fmt.Printf("c: %p\n", c)
	// var i int
	// fmt.Printf("i: %p\n", &i)
	// var str string
	// fmt.Printf("str: %p\n", &str)
	// var arr = make([][]bool, 0)
	// fmt.Printf("arr: %v\n", arr)
}
