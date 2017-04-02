---
title: 只要用 kubeadm 小朋友都能部署 Kubernetes
date: 2016-9-29 17:08:54
layout: page
categories:
- Kubernetes
tags:
- Kubernetes
- Ubuntu
- CentOS
---
[kubeadm](https://kubernetes.io/docs/getting-started-guides/kubeadm/)是 Kubernetes 官方推出的部署工具，該工具實作類似 Docker swarm 一樣的部署方式，透過初始化 Master 節點來提供給 Node 快速加入，kubeadm 目前屬於測試環境用階段，但隨著時間推移會越來越多功能被支援，這邊可以看 [kubeadm Roadmap for v1.6](https://github.com/kubernetes/kubeadm/milestone/1) 來更進一步知道功能發展狀態。

本環境安裝資訊：
* Kubernetes v1.6.0(2017/03/29 Update).
* Etcd v3
* Flannel v0.7.0
* Docker v1.13.1

<!--more-->

## 節點資訊
本次安裝作業系統採用`Ubuntu 16.04 Server`，測試環境為 Vagrant with Libvirt：

| IP Address  |   Role   |   CPU    |   Memory   |
|-------------|----------|----------|------------|
|172.16.35.12 |  master1 |    1     |     2G     |
|172.16.35.10 |  node1   |    1     |     2G     |
|172.16.35.11 |  node2   |    1     |     2G     |

> 目前 kubeadm 只支援在`Ubuntu 16.04+`、`CentOS 7`與`HypriotOS v1.0.1+`作業系統上使用。

## 事前準備
安裝前需要確認叢集滿足以下幾點：
* 所有節點網路可以溝通。
* 所有節點需要設定 APT 與 Yum Docker Repository：
```sh
$ sudo apt-key adv --keyserver "hkp://p80.pool.sks-keyservers.net:80" --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
$ echo 'deb https://apt.dockerproject.org/repo ubuntu-xenial main' | sudo tee /etc/apt/sources.list.d/docker.list
```
> `2017.3.1` Docker 更改了版本命名，變成 Docker v17.03.0-ce，而目前測試不支援，可能會在 Kubernetes v1.6 一起 Release。

* 所有節點需要設定 APT 與 Yum Kubernetes Repository：
```sh
$ curl -s "https://packages.cloud.google.com/apt/doc/apt-key.gpg" | apt-key add -
$ echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
```
> 若是 CentOS 7 則執行以下方式：
```sh
$ cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=http://yum.kubernetes.io/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
       https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
```

* CentOS 7 要額外確認 SELinux 或 Firewall 關閉。

## Kubernetes Master 建立
首先更新 APT 來源，並且安裝 Kubernetes 元件與工具：
```sh
$ sudo apt-get update && sudo apt-get install -y kubelet kubeadm kubectl kubernetes-cni docker-engine=1.13.1-0~ubuntu-xenial
```

完成後就可以開始進行初始化 Master，這邊需要進入`root`使用者執行以下指令：
```sh
$ sudo su -
$ kubeadm token generate
b0f7b8.8d1767876297d85c

$ kubeadm init --service-cidr 10.96.0.0/12 \
--pod-network-cidr 10.244.0.0/16 \
--apiserver-advertise-address 172.16.35.12 \
--token b0f7b8.8d1767876297d85c

...
kubeadm join --token=b0f7b8.8d1767876297d85c 172.16.35.12
```

當出現如上面資訊後，表示 Master 初始化成功，不過這邊還是一樣透過 kubectl 測試一下：
```sh
$ kubectl get node
NAME      STATUS         AGE
master1   Ready,master   6m
```

當執行正確後要接著部署網路，但要注意`一個叢集只能用一種網路`，這邊採用 Flannel：
```sh
$ curl -sSL "https://rawgit.com/coreos/flannel/master/Documentation/kube-flannel.yml" | kubectl create -f -
configmap "kube-flannel-cfg" created
daemonset "kube-flannel-ds" created
```
> 若要使用 Weave 則執行以下：
```sh
$ kubectl apply -f "https://git.io/weave-kube"
```
> 其他可以參考 [Networking and Network Policy](https://kubernetes.io/docs/admin/addons/)。

確認 Flannel 部署正確：
```sh
$ kubectl get po
NAME                    READY     STATUS    RESTARTS   AGE
kube-flannel-ds-lx4ww   2/2       Running   0          2m

$ ip -4 a show flannel.1
5: flannel.1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc noqueue state UNKNOWN group default
    inet 10.244.0.0/32 scope global flannel.1
       valid_lft forever preferred_lft forever

$ route -n
Kernel IP routing table
Destination     Gateway         Genmask         Flags Metric Ref    Use Iface
10.244.0.0      0.0.0.0         255.255.0.0     U     0      0        0 flannel.1
```

## Kubernetes Node 建立
首先更新 APT 來源，並且安裝 Kubernetes 元件與工具：
```sh
$ sudo apt-get update
$ sudo apt-get install -y kubelet kubeadm kubernetes-cni docker-engine=1.13.1-0~ubuntu-xenial
```

完成後就可以開始加入 Node，這邊需要進入`root`使用者執行以下指令：
```sh
$ kubeadm join --token b0f7b8.8d1767876297d85c 172.16.35.12
...
Run 'kubectl get nodes' on the master to see this machine join.
```

回到`master1`查看節點狀態：
```sh
$ kubectl  get node
NAME      STATUS         AGE
master1   Ready,master   5m
node1     Ready          3m
node2     Ready          28s
```

## Add-ons 建立
當完成後就可以建立一些 Addons，如 Dashboard。這邊執行以下指令進行建立：
```sh
$ curl -sSL https://rawgit.com/kubernetes/dashboard/master/src/deploy/kubernetes-dashboard.yaml | kubectl create -f -
```

確認沒問題後，透過 kubectl 查看：
```sh
kubectl get svc --namespace=kube-system
NAME                   CLUSTER-IP       EXTERNAL-IP   PORT(S)         AGE
kube-dns               10.96.0.10       <none>        53/UDP,53/TCP   36m
kubernetes-dashboard   10.111.162.184   <nodes>       80:32546/TCP    33s
```

最後就可以存取 [Kube Dashboard](http://172.16.35.12:32546)

## 簡單部署一個微服務
這邊利用 Weave 公司提供的微服務來驗證系統，透過以下方式建立：
```sh
$ kubectl create namespace sock-shop
$ kubectl apply -n sock-shop -f "https://github.com/microservices-demo/microservices-demo/blob/master/deploy/kubernetes/complete-demo.yaml?raw=true"
```

接著透過 kubectl 查看資訊：
```sh
$ kubectl describe svc front-end -n sock-shop
$ kubectl get pods -n sock-shop
```

最後存取 http://172.16.35.12:30001 即可看到服務的 Frontend。
