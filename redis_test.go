package main

import (
	"context"
	"testing"

	"github.com/alicebob/miniredis/v2"
	"github.com/stretchr/testify/assert"
)

func TestNewRedisClient(t *testing.T) {
	s, err := miniredis.Run()
	assert.Nil(t, err)
	client := NewRedisClient(s.Addr())
	client.Set(context.Background(), "abc", 123, 86400)
	res, err := client.Get(context.Background(), "abc").Result()
	assert.Nil(t, err)
	assert.True(t, res == "123")
}
