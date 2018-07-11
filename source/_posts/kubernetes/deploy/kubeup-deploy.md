---
title: kube-up 腳本部署 Kubernetes 叢集(Deprecated)
date: 2016-01-16 17:08:54
catalog: true
categories:
- Kubernetes
tags:
- Kubernetes
- Docker
- Ubuntu
---
Kubernetes 提供了許多雲端平台與作業系統的安裝方式，本篇將使用官方腳本`kube-up.sh`來部署 Kubernetes 到 Ubuntu 14.04 系統上。其他更多平台的部署可以參考 [Creating a Kubernetes Cluster](https://kubernetes.io/docs/getting-started-guides/)。

本環境安裝資訊：
* Kubernetes v1.5.4
* Etcd v2.3.0
* Flannel v0.5.5
* Docker v1.13.1

<!--more-->

## 節點資訊
本次安裝作業系統採用`Ubuntu 14.04 Server`，測試環境為 OpenStack VM 與實體主機：

| IP Address  |   Role   |   CPU    |   Memory   |
|-------------|----------|----------|------------|
|172.16.35.12 |  master1 |    2     |     4G     |
|172.16.35.10 |  node1   |    2     |     4G     |
|172.16.35.11 |  node2   |    2     |     4G     |

> 這邊 master 為主要控制節點，node 為應用程式工作節點。

## 事前準備
安裝前需要確認叢集滿足以下幾點：
* 目前官方只測試過 `Ubuntu 14.04`，官方說法是 15.x 也沒問題，但 16.04 上我測試無法自動完成，要自己補上各種服務的 Systemd 腳本。
* 部署節點可以透過 SSH 與其他節點溝通，並且是無密碼登入，以及有 Sudoer 權限。
* 所有節點需要安裝`Docker`或`rtk`引擎。安裝方式為以下：

```sh
$ curl -fsSL "https://get.docker.com/" | sh
$ sudo iptables -P FORWARD ACCEPT
```

## 部署 Kubernetes 叢集
首先下載官方 Release 的原始碼程式：
```sh
$ curl -sSL "https://github.com/kubernetes/kubernetes/archive/v1.5.4.tar.gz" | tar zx
$ mv kubernetes-1.5.4 kubernetes
```

接著編輯`kubernetes/cluster/ubuntu/config-default.sh`設定檔，修改以下內容：
```sh
export nodes=${nodes:-"ubuntu@172.16.35.12 ubuntu@172.16.35.10 ubuntu@172.16.35.11"}
export role="ai i i"
export NUM_NODES=${NUM_NODES:-3}
export SERVICE_CLUSTER_IP_RANGE=192.168.3.0/24
export FLANNEL_NET=172.16.0.0/16
SERVICE_NODE_PORT_RANGE=${SERVICE_NODE_PORT_RANGE:-"30000-32767"}
```

設定要部署的 Kubernetes 版本環境參數：
```sh
export KUBE_VERSION=1.5.4
export FLANNEL_VERSION=0.5.5
export ETCD_VERSION=2.3.0
export KUBERNETES_PROVIDER=ubuntu
```

然後進入到`kubernetes/cluster`目錄，並執行以下指令：
```sh
$ sudo sed -i 's/verify-kube-binaries//g' kube-up.sh
$ ./kube-up.sh
...
Cluster validation succeeded
Done, listing cluster services:

Kubernetes master is running at http://172.16.35.12:8080
```

當看到上述資訊即表示成功部署，這時候進入到`cluster/ubuntu/binaries`目錄複製 kubectl 工具：
```sh
$ sudo cp kubectl /usr/local/bin/
```

最後透過 kubectl 工具來查看叢集節點是否成功加入：
```sh
$ kubectl get nodes

NAME           STATUS    AGE
172.16.35.12   Ready     2m
172.16.35.10   Ready     2m
172.16.35.11   Ready     2m
```

## (Option)部署 Add-ons
若要部署 kubernetes Dashboard 與 DNS 等額外服務的話，要修改`kubernetes/cluster/ubuntu/config-default.sh`設定檔，修改一下內容：
```sh
ENABLE_CLUSTER_MONITORING="${KUBE_ENABLE_CLUSTER_MONITORING:-true}"
ENABLE_CLUSTER_UI="${KUBE_ENABLE_CLUSTER_UI:-true}"
ENABLE_CLUSTER_DNS="${KUBE_ENABLE_CLUSTER_DNS:-true}"
DNS_SERVER_IP=${DNS_SERVER_IP:-"192.168.3.10"}
DNS_DOMAIN=${DNS_DOMAIN:-"cluster.local"}
```
> 通常基本款大概為 Dashboard、DNS、Monitoring 與 Logging，。

修改完成後，進入到`kubernetes/cluster/ubuntu`目錄，並執行以下指令：
```sh
$ KUBERNETES_PROVIDER=ubuntu ./deployAddons.sh
```

透過 kubectl 查看資訊，這邊服務屬於系統的，所以預設會被分到`kube-system`命名空間：
```sh
$ kubectl get pods --namespace=kube-system
```

最後就可以透過瀏覽器查看 [Dashboard](http://172.16.35.12:8080/ui)。

## 建立 Nginx 應用程式
Kubernetes 可以選擇使用指令直接建立應用程式與服務，或者撰寫 YAML 與 JSON 檔案來描述部署應用程式的配置，以下將使用兩種方式建立一個簡單的 Nginx 服務。

### 利用 ad-hoc 指令建立
kubectl 提供了 run 指令來快速建立應用程式部署，如下建立 Nginx 應用程式：
```sh
$ kubectl run nginx --image=nginx
$ kubectl get pods -o wide

NAME                    READY     STATUS    RESTARTS   AGE       IP            NODE
nginx-701339712-w5wlq   1/1       Running   0          26m       172.16.86.2   172.16.35.11
```

而當應用程式(deploy)被建立後，我們還需要透過 Kubernetes Service 來提供給外部網路存取應用程式，如下指令：
```sh
$ kubectl expose deploy nginx --port 80 --type NodePort
$ kubectl get svc -o wide
```

完成後要接著建立 svc（Service）來提供外部網路存取應用程式，使用以下指令建立：
```sh
$ kubectl expose rc nginx --port=80 --type=NodePort
$ kubectl get svc

NAME         CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
kubernetes   192.168.3.1     <none>        443/TCP        37m
nginx        192.168.3.199   <nodes>       80:31764/TCP   30m
```
> 這邊採用`NodePort`，即表示任何節點 IP 位址的`31764` Port 都會 Forward 到 Nginx container 的`80` Port。

若想刪除應用程式與服務的話，可以透過以下指令：
```sh
$ kubectl delete deploy nginx
$ kubectl delete svc nginx
```

### 撰寫 YAML 檔案建立
Kubernetes 支援了 JSON 與 YAML 來描述要部署的應用程式資訊，這邊撰寫`nginx-dp.yaml`來部署 Nginx 應用：
```
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: nginx
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.7.9
        ports:
        - containerPort: 80
```

接著建立 Service 來提供存取服務，這邊撰寫`nginx-svc.yaml`來建立服務：
```
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  type: NodePort
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
    nodePort: 30000
  selector:
    app: nginx
```

然後透過 kubectl 指令來指定檔案建立：
```sh
$ kubectl create -f nginx-dp.yaml
deployment "nginx" created

$ kubectl create -f nginx-svc.yaml
service "nginx-service" created
```

完成後，可以查看一下資訊：
```sh
$ kubectl get svc,pods,rc -o wide

NAME                CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE       SELECTOR
svc/kubernetes      192.168.3.1     <none>        443/TCP        51m       <none>
svc/nginx-service   192.168.3.155   <nodes>       80:30000/TCP   1m        app=nginx

NAME                        READY     STATUS    RESTARTS   AGE       IP             NODE
po/nginx-4087004473-0wrbs   1/1       Running   0          2m        172.16.101.2   172.16.35.10
```

最後要刪除的話，直接將 create 改成使用`delete`即可：
```sh
$ kubectl delete -f nginx-dp.yaml
$ kubectl delete -f nginx-svc.yaml
```

## 其他 Kubernetes 網路技術
Kubernetes 支援多種網路整合，若 Flannel 用不爽可以改以下幾種：
* [OpenVSwitch with GRE/VxLAN](https://github.com/kubernetes/kubernetes/blob/master/docs/admin/ovs-networking.md)
* [Linux Bridge L2 networks](http://blog.oddbit.com/2014/08/11/four-ways-to-connect-a-docker/)
* [Weave](https://github.com/zettio/weave)
* [Calico](https://github.com/Metaswitch/calico)(使用 BGP Routing)
