package config

type Hello struct {
	Name string `json:"name"`
	Age  int    `json:"age"`
}

type Config struct {
	Hello Hello
}
