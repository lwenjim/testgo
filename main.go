package main

func main() {
	//redis := redis.NewClient(&redis.Options{Addr: "127.0.0.1:6379"})

	//for message := range redis.PSubscribe("abc").Channel() {
	//	fmt.Printf("payload:%s, channel:%s\n", message.Payload, message.Channel)
	//}

	//redis.Publish("abc", "123")

	//res, _ := redis.PubSubChannels("*").Result()
	//println(strings.Join(res, ""))

	//message := redis.Subscribe("a")
	//defer message.Close()
	//for msg := range message.Channel() {
	//	fmt.Printf("channel:%s, payLoad:%s", msg.Channel, msg.Payload)
	//}

	//pipe := redis.TxPipeline()
	//defer pipe.Close()
	//pipe.Set("lwenjim", "aaa", 0)
	//pipe.Exec()
	//result, _ := redis.Get("lwenjim").Result()
	//println(result)

	//res, _ := redis.Eval("return redis.call('get', KEYS[1])", []string{"a"}).String()
	//println(res)

	//res := redis.ScriptLoad("return redis.call('get', KEYS[1])").String()
	//res2, _ := redis.EvalSha("4e6d8fc8bb01276962cce5371fa795a7763657ae", []string{"a"}).String()
	//println(res2)

	//println(redis.Time().String())

	//println(redis.Info().String())

	//println(redis.DBSize().String())

	//println(redis.ClientList().String())

	//println(redis.ClientGetName().String())

	//println(redis.RandomKey().String())
}
