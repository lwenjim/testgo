package main

import (
	"context"
	"github.com/lwenjim/code/chapter8/multiple-services/service"
	"google.golang.org/grpc"
	"google.golang.org/grpc/test/bufconn"
	"log"
	"net"
	"testing"
)

func startTestGrpcServer() (*grpc.Server, *bufconn.Listener) {
	l := bufconn.Listen(10)
	s := grpc.NewServer()
	registerServices(s)
	go func() {
		err := startServer(s, l)
		if err != nil {
			log.Fatal(err)
		}
	}()
	return s, l
}

func TestRepoService(t *testing.T) {
	s, l := startTestGrpcServer()
	defer s.GracefulStop()

	bufconnDialer := func(ctx context.Context, addr string) (net.Conn, error) {
		return l.Dial()
	}

	client, err := grpc.DialContext(context.Background(), "", grpc.WithInsecure(), grpc.WithContextDialer(bufconnDialer))
	if err != nil {
		t.Fatal(err)
	}
	repoClient := service.NewRepoClient(client)
	resp, err := repoClient.GetRepos(context.Background(), &service.RepoGetRequest{CreatorId: "user-123", Id: "repo-123"})
	if err != nil {
		t.Fatal(err)
	}
	if len(resp.Repo) != 1 {
		t.Fatalf("Expected to get back 1 repo, get back: %d repos", len(resp.Repo))
	}

	getId := resp.Repo[0].Id
	getOwnerId := resp.Repo[0].Owner.Id

	if getId != "repo-123" {
		t.Errorf("Expected Repo ID to be: repo-123, Got:%s", getId)
	}
	if getOwnerId != "user-123" {
		t.Errorf("Expected Creator ID to be:user-123, Got:%s", getOwnerId)
	}
}
