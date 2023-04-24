package main

import (
	"context"
	"github.com/lwenjim/code/chapter8/multiple-services/service"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/reflection"
	"google.golang.org/grpc/status"
	"log"
	"net"
	"os"
	"strings"
)

type repoService struct {
	service.UnimplementedRepoServer
}

type userService struct {
	service.UnimplementedUsersServer
}

func (s userService) GetUser(ctx context.Context, in *service.UserGetRequest) (*service.UserGetReply, error) {
	log.Printf("Received request for user with Email: %s Id: %s\n", in.Email, in.Id)
	components := strings.Split(in.Email, "@")
	if len(components) != 2 {
		return nil, status.Error(codes.InvalidArgument, "Invalid email address specified")
	}
	u := service.User{
		Id:        in.Id,
		FirstName: components[0],
		LasttName: components[1],
		Age:       36,
	}
	return &service.UserGetReply{
		User: &u,
	}, nil
}

func (s *repoService) GetRepos(ctx context.Context, in *service.RepoGetRequest) (*service.RepoGetReply, error) {
	log.Printf("Received request for repo with CreateId: %s Id:%s\n", in.CreatorId, in.Id)
	repo := service.Repository{
		Id:    in.Id,
		Name:  "test repo",
		Url:   "https://git.example.com/test/repo",
		Owner: &service.User{Id: in.CreatorId, FirstName: "Jane"},
	}
	r := service.RepoGetReply{
		Repo: []*service.Repository{&repo},
	}
	return &r, nil
}

func registerServices(s *grpc.Server) {
	service.RegisterRepoServer(s, &repoService{})
	service.RegisterUsersServer(s, &userService{})
}

func startServer(s *grpc.Server, l net.Listener) error {
	return s.Serve(l)
}

func main() {
	listenAddr := os.Getenv("LISTEN_ADDR")
	if len(listenAddr) == 0 {
		listenAddr = ":8880"
	}
	lis, err := net.Listen("tcp", listenAddr)
	if err != nil {
		log.Fatal(err)
	}
	s := grpc.NewServer()
	reflection.Register(s)
	registerServices(s)
	log.Fatal(startServer(s, lis))
}
