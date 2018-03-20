---
title: 利用 RBAC + SA 進行 Kubectl 權限控管
date: 2018-1-8 17:08:54
layout: page
categories:
- Kubernetes
tags:
- Kubernetes
- Kubernetes RBAC
- Docker
---
這邊說明如何建立不同 Service account user，以及 RBAC 來定義存取規則，並綁定於指定 Service account ，以對指定 Namespace 中資源進行存取權限控制。

<!--more-->

## Service account
Service account 一般使用情境方便是 Pod 中的行程呼叫 Kubernetes API 或者其他服務設計而成，這可能會跟 Kubernetes user account 有所混肴，但是由於 Service account 有別於 User account 是可以針對 Namespace 進行建立，因此這邊嘗試拿 Service account 來提供資訊給 kubectl 使用，並利用 RBAC 來設定存取規則，以限制該 Account 存取 API 的資源。

## RBAC
RBAC(Role-Based Access Control)是從 Kubernetes 1.6 開始支援的存取控制機制，叢集管理者能夠對 User 或 Service account 的角色設定指定資源存取權限，在 RBAC 中，權限與角色相互關聯，其透過成為適當的角色成員，以獲取這些角色的存取權限，這比起過去 ABAC 來的方便使用、更簡化等好處。

## 簡單範例
首先建立一個 Namespace 與 Service account：
```sh
$ kubectl create ns dev
$ kubectl -n dev create sa dev

# 取得 secret 資訊
$ SECRET=$(kubectl -n dev get sa dev -o go-template='{{range .secrets}}{{.name}}{{end}}')
```

建立一個 dev.conf 設定檔，添加以下內容：
```sh
$ API_SERVER="https://172.22.132.51:6443"
$ CA_CERT=$(kubectl -n dev get secret ${SECRET} -o yaml | awk '/ca.crt:/{print $2}')
$ cat <<EOF > dev.conf
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: $CA_CERT
    server: $API_SERVER
  name: cluster
EOF

$ TOKEN=$(kubectl -n dev get secret ${SECRET} -o go-template='{{.data.token}}')
$ kubectl config set-credentials dev-user \
    --token=`echo ${TOKEN} | base64 -d` \
    --kubeconfig=dev.conf

$ kubectl config set-context default \
    --cluster=cluster \
    --user=dev-user \
    --kubeconfig=dev.conf

$ kubectl config use-context default \
    --kubeconfig=dev.conf
```
> * 在不同作業系統中，`base64` 的 decode 指令不一樣，有些是 -D(OS X)。

新增 RBAC role 來限制 dev-user 存取權限:
```sh
$ cat <<EOF > dev-user-role.yml
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  namespace: dev
  name: dev-user-pod
rules:
- apiGroups: ["*"]
  resources: ["pods", "pods/log"]
  verbs: ["get", "watch", "list", "update", "create", "delete"]
EOF

$ kubectl create rolebinding dev-view-pod \
    --role=dev-user-pod \
    --serviceaccount=dev:dev \
    --namespace=dev
```
> * apiGroups 為不同 API 的群組，如 rbac.authorization.k8s.io，["*"] 為允許存取全部。
> * resources 為 API 存取資源，如 pods、pods/log、pod/exec，["*"] 為允許存取全部。
> * verbs 為 API 存取方法，如 get、list、watch、create、update、 delete、proxy，["*"] 為允許存取全部。


透過 kubectl 確認權限設定沒問題：
```shell=
$ kubectl --kubeconfig=dev.conf get po
Error from server (Forbidden): pods is forbidden: User "system:serviceaccount:dev:dev" cannot list pods in the namespace "default"

$ kubectl -n dev --kubeconfig=dev.conf run nginx --image nginx --port 80 --restart=Never
$ kubectl -n dev --kubeconfig=dev.conf get po
NAME      READY     STATUS    RESTARTS   AGE
nginx     1/1       Running   0          39s

$ kubectl -n dev --kubeconfig=dev.conf logs -f nginx
10.244.102.64 - - [04/Jan/2018:06:42:36 +0000] "GET / HTTP/1.1" 200 612 "-" "curl/7.47.0" "-"

$ kubectl -n dev --kubeconfig=dev.conf exec -ti nginx sh
Error from server (Forbidden): pods "nginx" is forbidden: User "system:serviceaccount:dev:dev" cannot create pods/exec in the namespace "dev"
```
> * 也可以用`export KUBECONFIG=dev.conf`來設定使用的 config。
