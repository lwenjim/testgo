#! /bin/bash
# shellcheck disable=2086,2068

openssl genrsa -out /tmp/haimaxy.key 2048

openssl req -new -key /tmp/haimaxy.key -out /tmp/haimaxy.csr -subj "/CN=haimaxy/O=youdianzhis"

openssl x509 -req -in /tmp/haimaxy.csr -CA /Users/jim/.minikube/ca.crt -CAkey /Users/jim/.minikube/ca.key -CAcreateserial -out /tmp/haimaxy.crt -days 500