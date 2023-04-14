package main

import (
<<<<<<< HEAD
=======
	"fmt"
	"io"
	"net/http"
	"net/http/httputil"
	"os"
>>>>>>> 6c95224d651c4a65bef49ec87c91a0b5db36089a
	"testing"
	"time"
)

<<<<<<< HEAD
func Test_main(t *testing.T) {
	println(time.Now().Format("2006-01-02"))
=======
func CustomTimer(w io.Writer) func(http.RoundTripper) http.RoundTripper {
	return func(rt http.RoundTripper) http.RoundTripper {
		func1 := func(req *http.Request) (*http.Response, error) {
			startTime := time.Now()
			defer func() {
				_, _ = fmt.Fprintf(w, ">>> request duration: %s", time.Since(startTime))
			}()
			return rt.RoundTrip(req)
		}
		return internalRoundTripper(func1)
	}
}

func DumpResponse(includeBody bool) func(http.RoundTripper) http.RoundTripper {
	return func(rt http.RoundTripper) http.RoundTripper {
		func1 := func(req *http.Request) (resp *http.Response, err error) {
			defer func() {
				if err == nil {
					o, err := httputil.DumpResponse(resp, includeBody)
					if err != nil {
						panic(err)
					}
					fmt.Println(string(o))
				}
			}()
			return rt.RoundTrip(req)
		}
		return internalRoundTripper(func1)
	}
}

func AddHeader(key, value string) func(http.RoundTripper) http.RoundTripper {
	return func(rt http.RoundTripper) http.RoundTripper {
		func1 := func(req *http.Request) (*http.Response, error) {
			header := req.Header
			if header == nil {
				header = make(http.Header)
			}
			header.Set(key, value)
			return rt.RoundTrip(req)
		}
		return internalRoundTripper(func1)
	}
}

type internalRoundTripper func(*http.Request) (*http.Response, error)

func (rt internalRoundTripper) RoundTrip(req *http.Request) (*http.Response, error) {
	return rt(req)
}

func Chain(rt http.RoundTripper, middlewares ...func(http.RoundTripper) http.RoundTripper) http.RoundTripper {
	if rt == nil {
		rt = http.DefaultTransport
	}
	rt = middlewares[0](rt)
	rt = middlewares[1](rt)
	rt = middlewares[2](rt)
	return rt
}

func Test_main(t *testing.T) {
	chain := Chain(
		nil,
		AddHeader("key", "value"),
		CustomTimer(os.Stdout),
		DumpResponse(false),
	)
	var c = http.Client{
		Transport: chain,
	}
	resp, err := c.Get("https://www.baidu.com")
	if err != nil {
		fmt.Printf("err: %v\n", err)
		return
	}
	defer func() { _ = resp.Body.Close() }()
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		println(err)
		return
	}
	fmt.Println(string(data))
>>>>>>> 6c95224d651c4a65bef49ec87c91a0b5db36089a
}
