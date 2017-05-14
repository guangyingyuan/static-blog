---
title: Minikube 部署 Local 測試環境
date: 2016-10-23 17:08:54
layout: page
categories:
- Kubernetes
tags:
- Kubernetes
- Docker
---
[Minikube](https://github.com/kubernetes/minikube) 是提供簡單與快速部署本地 Kubernetes 環境的工具，透過執行虛擬機來執行單節點 Kubernetes 叢集，以便開發者使用 Kubernetes 與開發用。

本環境安裝資訊：
* Minikube v0.19.0
* Kubernetes v1.6.0

<!--more-->

## 事前準備
安裝前需要確認叢集滿足以下幾點：
* 安裝 `xhyve driver`, `VirtualBox` 或 `VMware Fusion`。
* 安裝 kubectl 工具。

```sh
$ curl -O "https://storage.googleapis.com/kubernetes-release/release/v1.6.0/bin/darwin/amd64/kubectl"
$ chmod +x kubectl && sudo mv kubectl /usr/local/bin/
```
> 如果是 Linux 使用者則使用下面 URL 取得：
```sh
$ curl -O "https://storage.googleapis.com/kubernetes-release/release/v1.6.0//bin/linux/amd64/kubectl"
$ chmod +x kubectl && sudo mv kubectl /usr/bin/
```

## 快速開始
Minikube 支援了許多作業系統，若是 OS X 的開發者，可以透過該指令安裝：
```sh
$ curl -Lo minikube https://storage.googl
eapis.com/minikube/releases/v0.19.0/minikube-darwin-amd64 && chmod +x minikube && sudo mv minikube /usr/local/bin/
```
> Linux 開發者則利用以下指令安裝：
```sh
$ curl -Lo minikube https://storage.googleapis.com/minikube/releases/v0.19.0/minikube-linux-amd64 && chmod +x minikube && sudo mv minikube /usr/local/bin/
```

下載完成後，就可以透過以下指令建立環境：
```sh
$ minikube get-k8s-versions
$ minikube start
Starting local Kubernetes v1.6.0 cluster...
Starting VM...
SSH-ing files into VM...
Setting up certs...
Starting cluster components...
Connecting to cluster...
Setting up kubeconfig...
Kubectl is now configured to use the cluster.
```

看到上述資訊表示已完成啟動 Kubernetes 虛擬機，這時候可以透過 kubectl 來查看資訊：
```sh
$ kubectl get node
NAME       STATUS    AGE       VERSION
minikube   Ready     10m       v1.6.0

$ kubectl get po -n kube-system
NAME                             READY     STATUS    RESTARTS   AGE
po/kube-addon-manager-minikube   1/1       Running   2          12m
po/kube-dns-268032401-wzgjx      3/3       Running   3          11m
po/kubernetes-dashboard-hdcp1    1/1       Running   1          11m

NAME                       CLUSTER-IP   EXTERNAL-IP   PORT(S)         AGE
svc/kube-dns               10.0.0.10    <none>        53/UDP,53/TCP   11m
svc/kubernetes-dashboard   10.0.0.198   <nodes>       80:30000/TCP    11m
```
> 新版本 Minikube 預設會自動啟動上述 Addons。這時可以透過瀏覽器進入 [Dashboard](http://192.168.99.100:30000/)。

取得虛擬機裡面的 Docker env：
```sh
$ eval $(minikube docker-env)
$ docker version
Client:
 Version:      1.13.1
 API version:  1.23
 Go version:   go1.7.5
 Git commit:   092cba3
 Built:        Wed Feb  8 08:47:51 2017
 OS/Arch:      darwin/amd64

Server:
 Version:      1.11.1
 API version:  1.23 (minimum version )
 Go version:   go1.5.4
 Git commit:   5604cbe
 Built:        Wed Apr 27 00:34:20 2016
 OS/Arch:      linux/amd64
 Experimental: false
```

若想要移除與刪除虛擬機的話，可以透過以下指令進行：
```sh
$ minikube stop
$ minikube delete
```

## 執行簡單測試應用程式
這邊利用 echoserver 來測試 Minikube 功能，首先透過以下指令啟動一個 Deployment：
```sh
$ kubectl run hello-minikube --image=gcr.io/google_containers/echoserver:1.4 --port=8080
$ kubectl get deploy,po
NAME                    DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
deploy/hello-minikube   1         1         1            1           11m

NAME                                READY     STATUS    RESTARTS   AGE
po/hello-minikube-938614450-31rtv   1/1       Running   0          11m
```

接著 expose 服務來進行存取：
```sh
$ kubectl expose deployment hello-minikube --type=NodePort
$ kubectl get svc
NAME             CLUSTER-IP   EXTERNAL-IP   PORT(S)          AGE
hello-minikube   10.0.0.164   <nodes>       8080:30371/TCP   4s
kubernetes       10.0.0.1     <none>        443/TCP          29m
```

最後透過 cURL 來存取服務：
```sh
$ curl $(minikube service hello-minikube --url)
CLIENT VALUES:
client_address=172.17.0.1
command=GET
real path=/
...
```
