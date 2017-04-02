---
title: 透過官方 Ansible 部署 Kubernetes
date: 2016-2-24 17:08:54
layout: page
categories:
- Kubernetes
tags:
- Kubernetes
- Docker
- Ansible
---
Kubernetes 提供了許多雲端平台與作業系統的安裝方式，本篇將使用官方 Ansible Playbook 來部署 Kubernetes 到 CentOS 7 系統上，其中 Kubernetes 將額外部署 Dashboard 與 DNS 等 Add-ons。其他更多平台的部署可以參考 [Creating a Kubernetes Cluster](https://kubernetes.io/docs/getting-started-guides/)。

<center>![](/images/kube/kube-ansible.png)</center>

本次安裝版本為：
* Kubernetes v1.5.2
* Etcd v3.1.0
* Flannel v0.5.5
* Docker v1.12.6

<!--more-->

## 節點資訊
本教學將以下列節點數與規格來進行部署 Kubernetes 叢集，作業系統採用`CentOS 7.x`：

| IP Address  |   Role   |   CPU    |   Memory   |
|-------------|----------|----------|------------|
|172.16.35.12 |  master1 |    2     |     4G     |
|172.16.35.10 |  node1   |    2     |     4G     |
|172.16.35.11 |  node2   |    2     |     4G     |

> 這邊 master 為主要控制節點，node 為應用程式工作節點。

## 預先準備資訊
首先安裝前要確認以下幾項都已將準備完成：
* 所有節點彼此網路互通，並且不需要 SSH 密碼即可登入。
* 所有主機擁有 Sudoer 權限。
* 所有節點需要設定`/etc/host`解析到所有主機。
* `master1`或部署節點需要安裝 Ansible 與相關套件：
```sh
$ sudo yum install -y epel-release
$ sudo yum install -y ansible python-netaddr git
```

## 部署 Kubernetes
首先透過 Git 工具來取得 Kubernetes 官方的 Ansible Playbook 專案，並進入到目錄：
```sh
$ git clone "https://github.com/kubernetes/contrib.git"
$ cd contrib/ansible
```

編輯`inventory/hosts`檔案(inventory)，並加入以下內容：
```
[masters]
master1

[etcd:children]
masters

[nodes]
node[1:2]
```

然後利用 Ansible ping module 來檢查節點是否可以溝通：
```sh
$ ansible -i inventory/hosts all -m ping
master1 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
node2 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
node1 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

編輯`inventory/group_vars/all.yml`檔案，並修改以下內容：
```
source_type: packageManager
cluster_name: cluster.kairen
networking: flannel
cluster_logging: true
cluster_monitoring: true
kube_dash: true
dns_setup: true
dns_replicas: 1
```
> 其他參數可自行選擇是否啟用。

(Option)編輯`roles/flannel/defaults/main.yaml`檔案，修改以下內容：
```
flannel_options: --iface=enp0s8
```
> 這邊主要解決 Vagrant 預設抓 NAT 網卡問題。

完成後進入到`scripts`目錄，並執行以下指令進行部署：
```sh
$ INVENTORY=../inventory/hosts ./deploy-cluster.sh
...
PLAY RECAP *********************************************************************
master1                    : ok=229  changed=93   unreachable=0    failed=0
node1                      : ok=126  changed=58   unreachable=0    failed=0
node2                      : ok=122  changed=58   unreachable=0    failed=0
```

經過一段時候就會完成，若沒有發生任何錯誤的話，就可以令用 kubectl 查看節點資訊：
```sh
$ kubectl get nodes
NAME      STATUS    AGE
node1     Ready     3m
node2     Ready     3m
```

查看系統命名空間的 pod 與 svc 資訊：
```sh
$ kubectl get svc --all-namespaces
NAMESPACE     NAME                    CLUSTER-IP       EXTERNAL-IP   PORT(S)             AGE
default       kubernetes              10.254.0.1       <none>        443/TCP             3h
kube-system   elasticsearch-logging   10.254.164.5     <none>        9200/TCP            3h
kube-system   heapster                10.254.213.162   <none>        80/TCP              3h
kube-system   kibana-logging          10.254.176.124   <none>        5601/TCP            3h
kube-system   kube-dns                10.254.0.10      <none>        53/UDP,53/TCP       3h
kube-system   kubedash                10.254.68.80                   80/TCP              3h
kube-system   kubernetes-dashboard    10.254.84.138    <none>        80/TCP              3h
kube-system   monitoring-grafana      10.254.193.233   <none>        80/TCP              3h
kube-system   monitoring-influxdb     10.254.135.115   <none>        8083/TCP,8086/TCP   3h
```
> 完成後，透過瀏覽器進入 [Dashboard](http://k8s-master:8080/ui)。

## Targeted runs
Ansible 提供 Tag 來指定執行或者忽略，這邊腳本也提供了該功能，如以下只部署 Etcd：
```sh
$ ./deploy-cluster.sh --tags=etcd
```
