---
title: 自製 Kubernetes Ansible 快速部署實體機 HA 叢集
date: 2017-02-19 17:08:54
layout: page
categories:
- Kubernetes
tags:
- Kubernetes
- Docker
- Ansible
---
本篇說明如何透過 [KaiRen Kubernetes Ansible](https://github.com/kairen/kube-ansible) 部署多節點實體機 Kubernetes 叢集。

本安裝各軟體版本如下：
* Kubernetes v1.6.2
* Etcd v3.1.6
* Flannel v0.7.1
* Docker v17.04.0-ce

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
$ git clone "https://github.com/kairen/kube-ansible.git" -b dev
$ cd kube-ansible
```

然後編輯`inventory`檔案，來加入要部署的節點角色：
```
[etcd]
172.20.3.[91:93]

[masters]
172.20.3.[91:93]

[sslhost]
172.20.3.91

[nodes]
172.20.3.[94:98]

[cluster:children]
masters
nodes
```

完成後接著編輯`group_vars/all.yml`，來根據需求設定參數，範例如下：
```
# Kubernetes component version
kube_version: 1.6.2

# Network plugin
network: flannel
pod_network_cidr: "10.244.0.0/16"

# Kubernetes service 內部網路 IP range(預設即可)
cluster_subnet: 192.160.0
kubernetes_service_ip: "{{ cluster_subnet }}.1"
service_ip_range: "{{ cluster_subnet }}.0/12"
service_node_port_range: 30000-32767

# apiserver lb 與 vip
lb_vip_address: 172.20.3.90
lb_api_url: "https://{{ lb_vip_address }}"
api_secure_port: 5443

sslcert_enable: true

# 額外認證方式
extra_auth:
  basic:
    accounts:
    - 'p@ssw0rd,admin,admin'

# 若有內部 registry 則需要設定
insecure_registrys:
# - "gcr.io"

# Kubernetes Addons 設定
kube_dash: true  # Dashboard 服務

kube_dns: true # DNS 服務

kube_proxy: true # Kubernetes proxy 元件
kube_proxy_mode: iptables # 如果要部署 Ceph on Kubernetes 需要改成 'userspace'

kube_logging: true # EFK 服務
kube_monitoring: true # Heapster + Influxdb + Grafana 服務
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

若想要更新特定元件可以使用以下方式：
```sh
$ ansible-playbook cluster.yml --tags etcd
```

## 驗證叢集
當完成上述步驟後，就可以在任一台`master`節點進行操作 Kubernetes：
```sh
$ kubectl get po -n kube-system
NAME                                    READY     STATUS    RESTARTS   AGE
...
kubernetes-dashboard-1765530275-rxbkw   1/1       Running   0          1m
```
> 確認都是`Running`後，就可以進入 [Dashboard](https://172.20.3.90/ui)，輸入 admin 與 p@ssw0rd 來登入。

接著透過 Etcd 來查看目前 Leader 狀態：
```sh
$ etcdctl member list
2de3b0eee054a36f: name=master1 peerURLs=http://172.20.3.91:2380 clientURLs=http://172.20.3.91:2379 isLeader=false
75809e2ee8d8d4b4: name=master2 peerURLs=http://172.20.3.92:2380 clientURLs=http://172.20.3.92:2379 isLeader=false
af31edd02fc70872: name=master3 peerURLs=http://172.20.3.93:2380 clientURLs=http://172.20.3.93:2379 isLeader=true
```

## 重置叢集
若想要將整個叢集進行重置的話，可以使用以下方式：
```sh
$ ansible-playbook playbooks/reset.yml
```
