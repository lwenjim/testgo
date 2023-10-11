#!/usr/bin/env sh
# see https://www.qikqiak.com/post/use-rbac-in-k8s/


# openssl genrsa -out runtime/haimaxy.key 2048
# openssl req -new -key runtime/haimaxy.key -out runtime/haimaxy.csr -subj "/CN=haimaxy/O=youdianzhis"

openssl x509 -req -in runtime/haimaxy.csr -CA /Users/jim/.minikube/ca.crt -CAkey /Users/jim/.minikube/ca.key -CAcreateserial -out runtime/haimaxy.crt -days 500
kubectl config set-credentials haimaxy --client-certificate=runtime/haimaxy.crt  --client-key=runtime/haimaxy.key
kubectl config set-context haimaxy --cluster=minikube --namespace=kube-system --user=haimaxy


kubectl create -f ./haimaxy-role.yaml
kubectl create -f ./haimaxy-rolebinding.yaml
kubectl get pods --context=haimaxy



kubectl create sa haimaxy-sa -n kube-system
kubectl create -f haimaxy-sa-role.yaml
kubectl create -f haimaxy-sa-rolebinding.yaml
kubectl get secret -n kube-system |grep haimaxy-sa
kubectl get secret haimaxy-sa-token-qv5ph -o jsonpath="{.data.token}" -n kube-system |base64 -d


kubectl create -f haimaxy-sa2.yaml
kubectl create -f haimaxy-clusterolebinding.yaml