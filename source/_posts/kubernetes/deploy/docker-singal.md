---
title: Docker 建立單機 Kubernetes(已更新至 v1.5.4)
date: 2016-01-13 17:08:54
layout: page
categories:
- Kubernetes
tags:
- Kubernetes
- Docker
---
本篇將說明如何透過 Docker 來部署一個單機的 kubernetes。其架構圖如下所示：

![](/images/kube/singlenode-docker.png)

<!--more-->

## 事前準備
在開始安裝前，我們必須在部署的主機或虛擬機安裝與完成以下兩點：
* 確認安裝 Docker Engine 於主機作業系統。
```sh
$ curl -fsSL "https://get.docker.com/" | sh
$ sudo iptables -P FORWARD ACCEPT
```

* 定義要使用的 Kubernetes 版本，目前支援 1.2.0+ 版本。
```sh
$ export K8S_VERSION="1.5.4"
```

## 部署 Kuberentes 元件
完成上述後，透過執行以下指令進行部署：
```sh
$ sudo docker run -d \
--volume=/:/rootfs:ro \
--volume=/sys:/sys:ro \
--volume=/var/lib/docker/:/var/lib/docker:rw \
--volume=/var/lib/kubelet/:/var/lib/kubelet:rw \
--volume=/var/run:/var/run:rw \
--net=host \
--pid=host \
--privileged=true \
--name=kubelet \
gcr.io/google_containers/hyperkube-amd64:v${K8S_VERSION} \
/hyperkube kubelet \
--containerized \
--hostname-override="127.0.0.1" \
--address="0.0.0.0" \
--api-servers="http://localhost:8080" \
--config=/etc/kubernetes/manifests \
--cluster-dns=10.0.0.10 \
--allow-privileged=true --v=2
```

執行後，透過 Docker 指令查看是否成功：
```sh
$ docker ps
CONTAINER ID        IMAGE                                                    COMMAND                  CREATED              STATUS              PORTS               NAMES
bfb6461499fb        gcr.io/google_containers/hyperkube-amd64:v1.5.4          "/hyperkube kubele..."   4 minutes ago        Up 4 minutes                            kubelet
...
```
> 這邊會隨時間開啟其他 Component 的 Docker Container。

確認完成後，就可以下載 kubectl 來透過 API 管理叢集：
```sh
$ curl -O "https://storage.googleapis.com/kubernetes-release/release/v${K8S_VERSION}/bin/linux/amd64/kubectl"
$ chmod +x kubectl && sudo mv kubectl /usr/local/bin/
```

接著設定 kubectl config 來使用測試叢集：
```sh
$ kubectl config set-cluster test-doc --server=http://localhost:8080
$ kubectl config set-context test-doc --cluster=test-doc
$ kubectl config use-context test-doc
```

## 驗證安裝
當完成所有步驟後，就可以檢查節點狀態：
```sh
$ kubectl get nodes
NAME        STATUS    AGE
127.0.0.1   Ready     6m
```

查看系統命名空間的 pod 與 svc 資訊：
```sh
$ kubectl get po --all-namespaces
kubectl get po --all-namespaces
NAMESPACE     NAME                                    READY     STATUS             RESTARTS   AGE
kube-system   k8s-etcd-127.0.0.1                      1/1       Running            0          15m
kube-system   k8s-master-127.0.0.1                    4/4       Running            2          15m
kube-system   k8s-proxy-127.0.0.1                     1/1       Running            0          15m
kube-system   kube-addon-manager-127.0.0.1            2/2       Running            0          15m
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
NAME                    READY     STATUS    RESTARTS   AGE       NODE
nginx-198147104-u9lt6   1/1       Running   0          3m        127.0.0.1
```

透過指令檢查 Service：
```sh
$ kubectl get svc -o wide
NAME         CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE       SELECTOR
kubernetes   10.0.0.1     <none>        443/TCP   11m       <none>
nginx        10.0.0.133   <none>        80/TCP    3m        run=nginx
```

取得應用程式的 Service ip，並存取服務：
```sh
$ IP=$(kubectl get svc nginx --template={{.spec.clusterIP}})
$ curl ${IP}
```
