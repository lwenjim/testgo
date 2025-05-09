package examples

import (
	"testing"
	"time"

	"github.com/cheggaaa/pb/v3"
)

func TestProgressBar(t *testing.T) {
	count := 100
	bar := pb.StartNew(count)
	for i := 0; i < count; i++ {
		time.Sleep(time.Millisecond * 50)
		bar.Increment()
	}
	bar.Finish()
}
