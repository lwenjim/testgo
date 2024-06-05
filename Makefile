CC = gcc
CFLAGS = -g -O0

SRCS = $(wildcard ./cgo/*.c)
OBJS = $(patsubst %.c, %.o, $(SRCS))
SERVER_NAME = app

.PHONY: clean app

all: app go

$(SERVER_NAME): $(OBJS)
	$(CC) $(CFLAGS) $^ -o bin/$@

./cgo/%.o: ./cgo/%.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(OBJS)
	rm -f $(SERVER_NAME)

go:
	CGO_ENABLED=1 go build -ldflags='-s -w' -o bin/go-app
