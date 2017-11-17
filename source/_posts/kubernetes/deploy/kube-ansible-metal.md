---
title: kube-ansible 快速部署實體機 HA 叢集
date: 2017-02-19 17:08:54
layout: page
categories:
- Kubernetes
tags:
- Kubernetes
- Docker
- Ansible
---
本篇說明如何透過 [kube-ansible](https://github.com/kairen/kube-ansible) 部署多節點實體機 Kubernetes 叢集。

本安裝各軟體版本如下：
* Kubernetes v1.8.3
* Etcd v3.2.9
* Flannel v0.9.0
* Docker v1.13.0+(latest on v17.10.0-ce)

<!--more-->

而在 OS 部分以支援`Ubuntu 16.x`及`CentOS 7.x`的虛擬機與實體機部署。

## 節點資訊
本次安裝作業系統採用`Ubuntu 16.04 Server`，測試環境為實體主機：

| IP Address  |   Role   |   CPU    |   Memory   |
|-------------|----------|----------|------------|
|172.20.3.90  |  VIP     |          |            |
|172.20.3.91  |  master1 |    2     |     4G     |
|172.20.3.92  |  master2 |    2     |     4G     |
|172.20.3.93  |  master3 |    2     |     4G     |
|172.20.3.94  |  node1   |    4     |     8G     |
|172.20.3.95  |  node2   |    4     |     8G     |
|172.20.3.96  |  node3   |    4     |     8G     |
|172.20.3.97  |  node4   |    4     |     8G     |
|172.20.3.98  |  node5   |    4     |     8G     |

## 事前準備
安裝前需要確認以下幾個項目：
* 所有節點的網路之間可以互相溝通。
* `部署節點(這邊為 master1)`對其他節點不需要 SSH 密碼即可登入。
* 所有節點都擁有 Sudoer 權限，並且不需要輸入密碼。
* 所有節點需要安裝 `Python`。
* 所有節點需要設定`/etc/host`解析到所有主機。
* `部署節點(這邊為 master1)`需要安裝 Ansible。

Ubuntu 16.04 安裝 Ansible:
```sh
$ sudo apt-get install -y software-properties-common git cowsay
$ sudo apt-add-repository -y ppa:ansible/ansible
$ sudo apt-get update && sudo apt-get install -y ansible
```

CentOS 7 安裝 Ansible：
```sh
$ sudo yum install -y epel-release
$ sudo yum -y install ansible cowsay
```

## 部署 Kubernetes 叢集
首先透過 Git 取得 HA Kubernetes Ansible 的專案：
```sh
$ git clone "https://github.com/kairen/kube-ansible.git"
$ cd kube-ansible
```

然後編輯`inventory`檔案，來加入要部署的節點角色：
```
[etcds]
172.20.3.[91:93]

[masters]
172.20.3.[91:93]

[nodes]
172.20.3.[94:98]

[kube-cluster:children]
masters
nodes
```

完成後接著編輯`group_vars/all.yml`，來根據需求設定參數，範例如下：
```yml
# Kubenrtes version, only support 1.8.0+.
kube_version: 1.8.3

# CRI plugin,
# Supported runtime: docker, containerd.
cri_plugin: docker

# CNI plugin,
# Supported network: flannel, calico, canal, weave or router.
network: calico
pod_network_cidr: 10.244.0.0/16

# Kubernetes cluster network
cluster_subnet: 10.96.0
kubernetes_service_ip: "{{ cluster_subnet }}.1"
service_ip_range: "{{ cluster_subnet }}.0/12"
service_node_port_range: 30000-32767

# apiserver lb 與 vip
lb_vip_address: 172.20.3.90
lb_secure_port: 6443
lb_api_url: "https://{{ lb_vip_address }}:{{ lb_secure_port }}"

# 若有內部 registry 則需要設定
insecure_registrys:
# - "gcr.io"

# Core addons (Strongly recommend)
kube_dns: true
dns_name: cluster.local # cluster dns name
dns_ip: "{{ cluster_subnet }}.10"

kube_proxy: true
kube_proxy_mode: iptables # "ipvs(1.8+)", "iptables" or "userspace".

# Extra addons
kube_dashboard: true # Kubenetes dasobhard console.
kube_logging: false # EFK stack for Kubernetes
kube_monitoring: true # Grafana + Infuxdb + Heapster monitoring

# Ingress controller
ingress: true
ingress_type: nginx # 'nginx', 'haproxy', 'traefik'
```

確認`group_vars/all.yml`完成後，透過 ansible ping 來檢查叢集狀態：
```sh
$ ansible all -m ping
172.20.3.91 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
...
```

接著就可以透過以下指令進行部署叢集：
```sh
$ ansible-playbook cluster.yml
```

執行後需要等一點時間，當完成後就可以進入任何一台 Master 進行操作：
```sh
$ kubectl get node
NAME      STATUS            AGE
master1   Ready,master      3m
master2   Ready,master      3m
master3   Ready,master      3m
node1     Ready             1m
node2     Ready             1m
node3     Ready             1m
node4     Ready             1m
node5     Ready             1m
```

接著就可以部署 Addons 了，透過以下方式進行：
```sh
$ ansible-playbook addons.yml
```

## 驗證叢集
當完成上述步驟後，就可以在任一台`master`節點進行操作 Kubernetes：
```sh
$ kubectl get po -n kube-system
NAME                                    READY     STATUS    RESTARTS   AGE
...
kubernetes-dashboard-1765530275-rxbkw   1/1       Running   0          1m
```
> 確認都是`Running`後，就可以進入 [Dashboard](https://172.20.3.90:6443/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/)。

接著透過 Etcd 來查看目前 Leader 狀態：
```sh
$ export CA="/etc/etcd/ssl"
$ ETCDCTL_API=3 etcdctl \
    --cacert=${CA}/etcd-ca.pem \
    --cert=${CA}/etcd.pem \
    --key=${CA}/etcd-key.pem \
    --endpoints="https://172.20.3.91:2379" \
    etcdctl member list

2de3b0eee054a36f: name=master1 peerURLs=http://172.20.3.91:2380 clientURLs=http://172.20.3.91:2379 isLeader=false
75809e2ee8d8d4b4: name=master2 peerURLs=http://172.20.3.92:2380 clientURLs=http://172.20.3.92:2379 isLeader=false
af31edd02fc70872: name=master3 peerURLs=http://172.20.3.93:2380 clientURLs=http://172.20.3.93:2379 isLeader=true
```

## 重置叢集
若想要將整個叢集進行重置的話，可以使用以下方式：
```sh
$ ansible-playbook reset.yml
```
