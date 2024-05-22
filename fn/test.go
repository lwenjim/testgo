package fn

import "github.com/lwenjim/testgo/config"

func Say() {
	var config config.Config
	config.Hello.Name = "Lwenjim"
	config.Hello.Age = 25
}
