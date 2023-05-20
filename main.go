package main

import (
	"fmt"
	"net"
	"net/smtp"
	"time"

	smtpmock "github.com/mocktools/go-smtp-mock/v2"
)

func main() {
	// You can pass empty smtpmock.ConfigurationAttr{}. It means that smtpmock will use default settings
	server := smtpmock.New(smtpmock.ConfigurationAttr{
		LogToStdout:       true,
		LogServerActivity: true,
	})

	// To start server use Start() method
	if err := server.Start(); err != nil {
		fmt.Println(err)
	}

	// Server's port will be assigned dynamically after server.Start()
	// for case when portNumber wasn't specified
	hostAddress, portNumber := "127.0.0.1", server.PortNumber()

	// Possible SMTP-client stuff for iteration with mock server
	address := fmt.Sprintf("%s:%d", hostAddress, portNumber)
	timeout := time.Duration(2) * time.Second

	connection, _ := net.DialTimeout("tcp", address, timeout)
	client, _ := smtp.NewClient(connection, hostAddress)
	client.Hello("example.com")
	client.Quit()
	client.Close()

	// Each result of SMTP session will be saved as message.
	// To get access to server messages use Messages() method
	server.Messages()

	// To stop the server use Stop() method. Please note, smtpmock uses graceful shutdown.
	// It means that smtpmock will end all sessions after client responses or by session
	// timeouts immediately.
	if err := server.Stop(); err != nil {
		fmt.Println(err)
	}
}
