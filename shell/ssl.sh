#! /bin/bash
# shellcheck disable=2086,2068

openssl genrsa -out /tmp/server.key 2048

openssl req -new -key /tmp/server.key -out /tmp/server.csr -subj "/CN=server/O=youdianzhis"

openssl x509 -req -in /tmp/server.csr -CA /Users/jim/.minikube/ca.crt -CAkey /Users/jim/.minikube/ca.key -CAcreateserial -out /tmp/server.crt -days 500

openssl genrsa -out /tmp/haimaxy.key 2048

openssl req -new -key /tmp/haimaxy.key -out /tmp/haimaxy.csr -subj "/CN=haimaxy/O=youdianzhis"

openssl x509 -req -in /tmp/haimaxy.csr -CA /Users/jim/.minikube/ca.crt -CAkey /Users/jim/.minikube/ca.key -CAcreateserial -out /tmp/haimaxy.crt -days 500

for each in $(kubectl get ns -o jsonpath="{.items[*].metadata.name}" | grep -v kube-system);do
  echo kubectl delete ns $each
done
