#!/usr/bin/env bash
curl -d '{"name":"abc","user_qrcode":"DNTIYUSSg","group_qrcode":"_yd8GjOIg","end_time":1704762951,"is_multi_select":true,"is_anonymous":true,"option":["中国队","美国队"]}' https://devwww.jspp.com/vote/add
curl -d '{"user_qrcode":"DNTIYUSSg","group_qrcode":"_yd8GjOIg"}' https://devwww.jspp.com/vote/list
curl -d '{"user_qrcode":"DNTIYUSSg","topic_qrcode":"4fIOEVKIR","option_id":[1]}' https://devwww.jspp.com/vote/post
curl -d '{"user_qrcode":"DNTIYUSSg","topic_qrcode":"4fIOEVKIR"}' https://devwww.jspp.com/vote/record