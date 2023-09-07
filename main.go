package main

import (
	"context"
	"fmt"
	"time"

	"code.jspp.com/jspp/internal-tools/rpc"
	"google.golang.org/grpc"
	"google.golang.org/grpc/balancer/roundrobin"
	"google.golang.org/grpc/credentials/insecure"
)

func main() {
	conn, err := grpc.Dial("127.0.0.1:39090", grpc.WithDefaultServiceConfig(fmt.Sprintf(`{"LoadBalancingPolicy": "%s"}`, roundrobin.Name)), grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		fmt.Println(err)
		return
	}
	messageClient := rpc.NewMessageClient(conn)
	resp, err := messageClient.SetTimingRemind(context.Background(), &rpc.SetTimingRemindRequest{
		ExecuteTime: time.Now().Unix() + 30*int64(time.Minute),
		MessageItem: &rpc.MessageItem{
			Content: &rpc.MessageContent{
				Text: &rpc.TextMessage{
					Text:            "123",
					Markdown:        false,
					IsTimingMessage: false,
				},
			},
		},
	})
	if err != nil {
		fmt.Println(err)
		return
	}
	fmt.Printf("%#v", resp.Response.Result)

	resp2, err := messageClient.GetTimingReminds(context.TODO(), &rpc.GetTimingRemindsRequest{
		Auth: &rpc.BaseRequest{
			TokenRaw: []byte{},
			Token: &rpc.Token{
				UserId: 110,
			},
			RequestId: "",
		},
	})
	if err != nil {
		fmt.Println(err)
		return
	}
	fmt.Printf("%#v", resp2)
	for _, timingRemind := range resp2.TimingReminds {
		fmt.Printf("timingRemind.Content: %v\n", timingRemind.MessageItem.Content)
	}
}
