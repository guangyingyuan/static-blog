---
title: hyperkube 建立多節點 Kubernetes(Unrecommended)
date: 2016-01-14 17:08:54
layout: page
categories:
- Kubernetes
tags:
- Kubernetes
- Docker
---
本篇將說明如何透過 Docker 來部署一個多節點的 kubernetes 叢集。其架構圖如下所示：

![](/images/kube/multinode-docker.png)

本環境安裝資訊：
* Kubernetes v1.5.5
* Docker v17.03.0-ce

<!--more-->

## 節點資訊
本次安裝作業系統採用`Ubuntu 16.04 Server`，測試環境為 Vagrant with Libvirt 或 Vbox：

| IP Address  |   Role   |   CPU    |   Memory   |
|-------------|----------|----------|------------|
|172.16.35.12 |  master1 |    2     |     4G     |
|172.16.35.10 |  node1   |    2     |     4G     |
|172.16.35.11 |  node2   |    2     |     4G     |

> 這邊 master 為主要控制節點，node 為應用程式工作節點。

## 事前準備
安裝前需要確認叢集滿足以下幾點：
* 所有節點需要安裝`Docker`或`rtk`引擎。安裝方式為以下：

```sh
$ curl -fsSL "https://get.docker.com/" | sh
$ sudo iptables -P FORWARD ACCEPT
```

## Kubernetes 部署
這邊將分別部署 Master 與 Node(Worker) 節點。

### 建立 Master 節點
首先下載官方 Release 的原始碼程式：
```sh
$ git clone "https://github.com/kubernetes/kube-deploy"
```

接著進入部署目錄來進行部署動作，Master 執行以下指令：
```sh
$ export IP_ADDRESS="172.16.35.12"
$ cd kube-deploy/docker-multinode
$ ./master.sh
...
Master done!
```

執行後，透過 Docker 指令查看是否成功：
```sh
$ docker ps
CONTAINER ID        IMAGE                                                    COMMAND                  CREATED              STATUS              PORTS               NAMES
bfb6461499fb        gcr.io/google_containers/hyperkube-amd64:v1.5.5          "/hyperkube kubele..."   4 minutes ago        Up 4 minutes                            kubelet
...
```
> 這邊會隨時間開啟其他 Component 的 Docker Container。

確認完成後，就可以下載 kubectl 來透過 API 管理叢集：
```sh
$ curl -O "https://storage.googleapis.com/kubernetes-release/release/v1.5.5/bin/linux/amd64/kubectl"
$ chmod +x kubectl && sudo mv kubectl /usr/local/bin/
```

安裝好 kubectl 後就可以透過以下指令來查看資訊：
```sh
$ kubectl get nodes
NAME           STATUS    AGE
172.16.35.12   Ready     11s
```

查看系統命名空間的 pod 與 svc 資訊：
```sh
$ kubectl get po --all-namespaces
NAMESPACE     NAME                                    READY     STATUS    RESTARTS   AGE
kube-system   k8s-proxy-v1-bfdml                      1/1       Running   0          1m
kube-system   kube-dns-4101612645-fb1rn               4/4       Running   0          1m
kube-system   kubernetes-dashboard-3543765157-999p2   1/1       Running   0          1m
```

### 建立 Node(Worker) 節點
首先下載官方 Release 的原始碼程式：
```sh
$ git clone "https://github.com/kubernetes/kube-deploy"
```

接著進入部署目錄來進行部署動作，Node 執行以下指令：
```sh
$ export MASTER_IP="172.16.35.12"; export IP_ADDRESS="172.16.35.11"
$ cd kube-deploy/docker-multinode
$ ./worker.sh
...
+++ [0324 07:23:06] Done. After about a minute the node should be ready
```

## 驗證安裝
完成後可以查看所有節點狀態，執行以下指令：
```sh
$ kubectl get nodes
NAME           STATUS    AGE
172.16.35.10   Ready     3m
172.16.35.11   Ready     4m
172.16.35.12   Ready     1m
```

接著我們透過部署簡單的 Nginx 應用程式來驗證系統是否正常：
```sh
$ kubectl run nginx --image=nginx --port=80
deployment "nginx" created

$ kubectl expose deploy nginx --port=80
service "nginx" exposed
```

透過指令檢查 Pods：
```sh
$ kubectl get po -o wide
NAME                     READY     STATUS    RESTARTS   AGE       IP         NODE
nginx-3449338310-ttqp2   1/1       Running   0          32s       10.1.1.2   172.16.35.11
```

透過指令檢查 Service：
```sh
$ kubectl get svc -o wide
NAME         CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE       SELECTOR
kubernetes   10.0.0.1     <none>        443/TCP   47m       <none>
nginx        10.0.0.149   <none>        80/TCP    37s       run=nginx
```

取得應用程式的 Service ip，並存取服務：
```sh
$ IP=$(kubectl get svc nginx --template={{.spec.clusterIP}})
$ curl ${IP}
```
