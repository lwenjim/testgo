package examples

import (
	"fmt"
	"io"
	"net/http"
	"sync"
	"sync/atomic"
)

type Once struct {
	m    sync.Mutex
	done uint32
}

func (o *Once) Do(f func()) {
	if atomic.LoadUint32(&o.done) == 1 {
		return
	}
	o.m.Lock()
	defer o.m.Unlock()
	if o.done == 0 {
		defer atomic.StoreUint32(&o.done, 1)
		f()
	}
}

func TestMutex() {
	var a Once
	a.Do(func() {
		resp, err := http.Get("https://www.baidu.com")
		if err != nil {
			fmt.Println(err)
			return
		}
		txt, err := io.ReadAll(resp.Body)

		if err != nil {
			fmt.Println(err)
			return
		}
		fmt.Printf("txt: %v\n", string(txt))
	})
}
