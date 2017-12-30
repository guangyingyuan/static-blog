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
[kubeadm](https://kubernetes.io/docs/setup/independent/install-kubeadm/)是 Kubernetes 官方推出的部署工具，該工具實作類似 Docker swarm 一樣的部署方式，透過初始化 Master 節點來提供給 Node 快速加入，kubeadm 目前屬於測試環境用階段，但隨著時間推移會越來越多功能被支援，這邊可以看 [kubeadm Roadmap](https://github.com/kubernetes/kubeadm) 來更進一步知道功能發展狀態。
> 若想利用 Ansible 安裝的話，可以參考這邊 [kubeadm-ansible](https://github.com/kairen/kubeadm-ansible)。

本環境安裝資訊：
* Kubernetes v1.9.0
* Etcd v3
* Flannel v0.9.1
* Docker v17.05.0-ce

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
* 所有節點需要設定 APT Docker Repository：

```sh
$ sudo apt-key adv --keyserver "hkp://p80.pool.sks-keyservers.net:80" --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
$ echo 'deb https://apt.dockerproject.org/repo ubuntu-xenial main' | sudo tee /etc/apt/sources.list.d/docker.list
```
> CentOS 7 EPEL 有支援 Docker Package:
```sh
$ sudo yum install -y epel-release
```

* 所有節點需要設定 APT 與 Yum Kubernetes Repository：

```sh
$ curl -s "https://packages.cloud.google.com/apt/doc/apt-key.gpg" | sudo apt-key add -
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
* Kubernetes v1.8 要求關閉系統 Swap，若不關閉則需要修改 kubelet 設定參數，這邊可以利用以下指令關閉：

```sh
$ swapoff -a && sysctl -w vm.swappiness=0
```
> 記得`/etc/fstab`也要註解掉`SWAP`掛載。

## Kubernetes Master 建立
首先更新 APT 來源，並且安裝 Kubernetes 元件與工具：
```sh
$ sudo apt-get update && sudo apt-get install -y kubelet kubeadm kubectl kubernetes-cni docker-engine
```

完成後 Reload daemon：
```sh
$ systemctl daemon-reload
```

進行初始化 Master，這邊需要進入`root`使用者執行以下指令：
```sh
$ sudo su -
$ kubeadm token generate
b0f7b8.8d1767876297d85c

$ kubeadm init --service-cidr 10.96.0.0/12 \
               --kubernetes-version v1.9.0 \
               --pod-network-cidr 10.244.0.0/16 \
               --apiserver-advertise-address 172.16.35.12 \
               --token b0f7b8.8d1767876297d85c
# output               
...
kubeadm join --token b0f7b8.8d1767876297d85c 172.16.35.12:6443
```

當出現如上面資訊後，表示 Master 初始化成功，不過這邊還是一樣透過 kubectl 測試一下：
```sh
$ cp /etc/kubernetes/admin.conf ~/.kube/config
$ kubectl get node
NAME      STATUS    ROLES     AGE       VERSION
master1   Ready     master    10m       v1.8.4
```

當執行正確後要接著部署網路，但要注意`一個叢集只能用一種網路`，這邊採用 Flannel：
```sh
$ kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/v0.9.0/Documentation/kube-flannel.yml
clusterrole "flannel" created
clusterrolebinding "flannel" created
serviceaccount "flannel" configured
configmap "kube-flannel-cfg" configured
daemonset "kube-flannel-ds" configured
```
> * 若參數 `--pod-network-cidr=10.244.0.0/16` 改變時，在`kube-flannel.yml`檔案也需修改`net-conf.json`欄位的 CIDR。
* 若使用 Virtualbox 的話，請修改`kube-flannel.yml`中的 command 綁定 iface，如`command: [ "/opt/bin/flanneld", "--ip-masq", "--kube-subnet-mgr", "--iface=eth1" ]`。

確認 Flannel 部署正確：
```sh
$ kubectl get po -n kube-system
NAME                                         READY     STATUS    RESTARTS   AGE
kube-flannel-ds-3b66l                        1/1       Running   0          9s
kube-flannel-ds-m6874                        1/1       Running   0          9s
kube-flannel-ds-vmb38                        1/1       Running   0          9s
...

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
$ sudo apt-get update && sudo apt-get install -y kubelet kubeadm kubernetes-cni docker-engine
```

完成後 Reload daemon：
```sh
$ systemctl daemon-reload
```

完成後就可以開始加入 Node，這邊需要進入`root`使用者執行以下指令：
```sh
$ kubeadm join --token b0f7b8.8d1767876297d85c 172.16.35.12:6443
# output
...
Run 'kubectl get nodes' on the master to see this machine join.
```

回到`master1`查看節點狀態：
```sh
$ kubectl get node
NAME      STATUS    ROLES     AGE       VERSION
master1   Ready     master    10m       v1.8.4
node1     Ready     <none>    9m        v1.8.4
node2     Ready     <none>    9m        v1.8.4
```

為了多加利用資源這邊透過 taint 來讓 masters 也會被排程執行容器：
```sh
$ kubectl taint nodes --all node-role.kubernetes.io/master-
```

## Add-ons 建立
當完成後就可以建立一些 Addons，如 Dashboard。這邊執行以下指令進行建立：
```sh
$ kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/master/src/deploy/recommended/kubernetes-dashboard.yaml
```
> Dashboard 1.7.x 版本有做一些改變，會用到 SSL Cert，可參考這邊 [Installation](https://github.com/kubernetes/dashboard/wiki/Installation)。


確認沒問題後，透過 kubectl 查看：
```sh
kubectl get svc --namespace=kube-system
NAME                   CLUSTER-IP       EXTERNAL-IP   PORT(S)         AGE
kube-dns               10.96.0.10       <none>        53/UDP,53/TCP   36m
kubernetes-dashboard   10.111.162.184   <nodes>       80:32546/TCP    33s
```

最後就可以存取 [Kube Dashboard](https://172.16.35.12:6443/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/)。

在 1.7 版本以後的 Dashboard 將不再提供所有權限，因此需要建立一個 service account 來綁定 cluster-admin role：
```sh
$ kubectl -n kube-system create sa dashboard
$ kubectl create clusterrolebinding dashboard --clusterrole cluster-admin --serviceaccount=kube-system:dashboard
$ kubectl -n kube-system get sa dashboard -o yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  creationTimestamp: 2017-11-27T17:06:41Z
  name: dashboard
  namespace: kube-system
  resourceVersion: "69076"
  selfLink: /api/v1/namespaces/kube-system/serviceaccounts/dashboard
  uid: 56b880bf-d395-11e7-9528-448a5ba4bd34
secrets:
- name: dashboard-token-vg52j

$ kubectl -n kube-system describe secrets dashboard-token-vg52j
...
token:      eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJrdWJlcm5ldGVzL3NlcnZpY2VhY2NvdW50Iiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9uYW1lc3BhY2UiOiJrdWJlLXN5c3RlbSIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VjcmV0Lm5hbWUiOiJkYXNoYm9hcmQtdG9rZW4tdmc1MmoiLCJrdWJlcm5ldGVzLmlvL3NlcnZpY2VhY2NvdW50L3NlcnZpY2UtYWNjb3VudC5uYW1lIjoiZGFzaGJvYXJkIiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9zZXJ2aWNlLWFjY291bnQudWlkIjoiNTZiODgwYmYtZDM5NS0xMWU3LTk1MjgtNDQ4YTViYTRiZDM0Iiwic3ViIjoic3lzdGVtOnNlcnZpY2VhY2NvdW50Omt1YmUtc3lzdGVtOmRhc2hib2FyZCJ9.bVRECfNS4NDmWAFWxGbAi1n9SfQ-TMNafPtF70pbp9Kun9RbC3BNR5NjTEuKjwt8nqZ6k3r09UKJ4dpo2lHtr2RTNAfEsoEGtoMlW8X9lg70ccPB0M1KJiz3c7-gpDUaQRIMNwz42db7Q1dN7HLieD6I4lFsHgk9NPUIVKqJ0p6PNTp99pBwvpvnKX72NIiIvgRwC2cnFr3R6WdUEsuVfuWGdF-jXyc6lS7_kOiXp2yh6Ym_YYIr3SsjYK7XUIPHrBqWjF-KXO_AL3J8J_UebtWSGomYvuXXbbAUefbOK4qopqQ6FzRXQs00KrKa8sfqrKMm_x71Kyqq6RbFECsHPA
```
> 複製`token`，然後貼到 Kubernetes dashboard。

## 簡單部署一個服務
這邊利用 Weave 公司提供的服務來驗證系統，透過以下方式建立：
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

## 移除節點
最後，若要將現有節點移除的話，kubeadm 已經有內建的指令來完成這件事，只要執行以下即可：
```sh
$ kubeadm reset
```
