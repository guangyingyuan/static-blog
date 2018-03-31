---
title: Kubernetes v1.10.x HA 全手動苦工安裝教學(TL;DR)
date: 2018-03-28 17:08:54
layout: page
categories:
- Kubernetes
tags:
- Kubernetes
- Docker
- Calico
---
Kubernetes 目前已經提供越來越多種安裝方式，本篇延續過往`手動安裝方式`來部署 Kubernetes v1.10.x 版本的 High Availability 叢集，主要目的是學習 Kubernetes 安裝的一些元件關析與流程。若不想這麼累的話，可以參考 [Picking the Right Solution](https://kubernetes.io/docs/getting-started-guides/)來選擇自己最喜歡的方式。

本次安裝的軟體版本：
* Kubernetes v1.10.0.
* CNI v0.6.0.
* Etcd v3.2.9.
* Calico v3.0.1.
* Docker latest version.

<!--more-->

## 節點資訊
本教學將以下列節點數與規格來進行部署 Kubernetes 叢集，作業系統可採用`Ubuntu 16.x`與`CentOS 7.x`：

| IP Address | Hostname | CPU | Memory |
|------------|----------|-----|--------|
|192.16.35.11| k8s-m1   | 1   | 2G     |
|192.16.35.12| k8s-m2   | 1   | 2G     |
|192.16.35.13| k8s-m3   | 1   | 2G     |
|192.16.35.21| k8s-n1   | 1   | 2G     |
|192.16.35.22| k8s-n2   | 1   | 2G     |
|192.16.35.23| k8s-n2   | 1   | 2G     |

> * 這邊`m`為主要控制節點，`n`為應用程式工作節點。
> * 所有操作全部用`root`使用者進行(方便用)，以 SRE 來說不推薦。
> * 可以下載 [Vagrantfile](https://kairen.github.io/files/manual-v1.10/Vagrantfile) 來建立 Virtualbox 虛擬機叢集。不過需要注意機器資源是否足夠。

## 事前準備
開始安裝前需要確保以下條件已達成：
* 所有節點彼此網路互通，並且`k8s-m1` SSH 登入其他節點為 passwdless。
* 所有防火牆與 SELinux 已關閉。如 CentOS：

```sh
$ systemctl stop firewalld && systemctl disable firewalld
$ setenforce 0
$ vim /etc/selinux/config
SELINUX=disabled
```

* 所有節點需要設定`/etc/host`解析到所有叢集主機。

```
...
192.16.35.11 k8s-m1
192.16.35.12 k8s-m2
192.16.35.13 k8s-m3
192.16.35.21 k8s-n1
192.16.35.22 k8s-n2
192.16.35.23 k8s-n3
```

* 所有節點需要安裝 Docker CE 版本的容器引擎：

```sh
$ curl -fsSL "https://get.docker.com/" | sh
```
> 不管是在 `Ubuntu` 或 `CentOS` 都只需要執行該指令就會自動安裝最新版 Docker。
> CentOS 安裝完成後，需要再執行以下指令：
```sh
$ systemctl enable docker && systemctl start docker
```

* 所有節點需要設定`/etc/sysctl.d/k8s.conf`的系統參數。

```sh
$ cat <<EOF > /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

$ sysctl -p /etc/sysctl.d/k8s.conf
```

* 在所有節點下載 Kubernetes 二進制執行檔：

```sh
$ export KUBE_URL="https://storage.googleapis.com/kubernetes-release/release/v1.10.0/bin/linux/amd64"
$ wget "${KUBE_URL}/kubelet" -O /usr/local/bin/kubelet

# node 可以忽略安裝 kubectl
$ wget "${KUBE_URL}/kubectl" -O /usr/local/bin/kubectl
$ chmod +x /usr/local/bin/kubelet /usr/local/bin/kubectl
```

* 在`k8s-m1`需要安裝`CFSSL`工具，這將會用來建立 TLS certificates。

```sh
$ export CFSSL_URL="https://pkg.cfssl.org/R1.2"
$ wget "${CFSSL_URL}/cfssl_linux-amd64" -O /usr/local/bin/cfssl
$ wget "${CFSSL_URL}/cfssljson_linux-amd64" -O /usr/local/bin/cfssljson
$ chmod +x /usr/local/bin/cfssl /usr/local/bin/cfssljson
```

## Etcd 叢集
在開始安裝 Kubernetes 之前，需要先將一些必要系統建置完成，其中 Etcd 就是 Kubernetes 最重要的一環，Kubernetes 會將大部分資訊儲存於 Etcd 上，來提供給其他節點索取，以確保整個叢集運作與溝通正常。
