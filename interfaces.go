package main

import "io"

// Encoder 编码器
type Encoder interface {
	Encode(obj interface{}, w io.Writer) error
}