CC = gcc
CFLAGS = -g -O0

SRCS = $(wildcard ./cgo/c/*.c)
OBJS = $(patsubst %.c, %.o, $(SRCS))
SERVER_NAME = app

.PHONY: clean app

all: app go

$(SERVER_NAME): $(OBJS)
	$(CC) $(CFLAGS) $^ -o bin/$@

./cgo/c/%.o: ./cgo/c/%.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(OBJS)
	rm -f bin/$(SERVER_NAME)
	rm -f bin/go-app
	
go:
	CGO_ENABLED=1 go build -ldflags='-s -w' -o bin/go-app ./cgo
