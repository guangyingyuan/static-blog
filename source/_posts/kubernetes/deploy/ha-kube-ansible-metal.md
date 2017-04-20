---
title: HA Kubernetes Ansible 快速部署實體機 HA 叢集
date: 2017-02-19 17:08:54
layout: page
categories:
- Kubernetes
tags:
- Kubernetes
- Docker
- Ansible
---
本篇說明如何透過 [HA Kubernetes Ansible](https://github.com/kairen/ha-kube-ansible) 部署多節點實體機 Kubernetes 叢集。

本安裝各軟體版本如下：
* Kubernetes v1.6.1
* Etcd v3.1.5
* Flannel v0.7.0
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
$ sudo yum -y install ansible
```

## 部署 Kubernetes 叢集
首先透過 Git 取得 HA Kubernetes Ansible 的專案：
```sh
$ git clone "https://github.com/kairen/ha-kube-ansible.git"
$ cd ha-kube-ansible
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
```

完成後接著編輯`group_vars/all.yml`，來根據需求設定參數，範例如下：
```
docker_install_type: "package"
kube_install_type: "source"

# Kubernetes 內部叢集網路
kubernetes_service_ip: 192.160.0.1
service_ip_range: 192.160.0.0/12
service_node_port_range: 30000-32767

# API Servers 負載平衡與 VIP
lb_vip_address: 172.20.3.90 # 必須是沒有被 bind 的 IP
lb_api_url: https://172.20.3.90
api_secure_port: 5443

sslcert_create: true
masters_fqdn: ['kube.master1.com', 'kube.master2.com', 'kube.master3.com']

# 若有內部 registry 則需要設定
insecure_registrys:
# - "gcr.io"

# Etcd 資訊設定
etcd_version: 3.1.5

# Flannel 網路資訊
flannel: true
flannel_version: 0.7.0
flannel_key: /atomic.io/network
flannel_subnet: 172.16.0.0
flannel_prefix: 16
flannel_host_prefix: 24
flannel_backend: vxlan

kube_proxy: true
kube_proxy_mode: iptables

# 額外插件資訊(options)
kube_dash: true  
kube_dash_ip: 172.20.3.90
kube_dash_port: 80

kube_dns: true
dns_name: cluster.local
dns_ip: 192.160.0.10
dns_replicas: 1

kube_logging: true
logging_ip: 172.20.3.90
kibana_port: 5601
elasticsearch_port: 9200

kube_monitoring: true
monitoring_ip: 172.20.3.90
heapster_ip: 192.160.0.11
heapster_port: 80
grafana_port: 100
influx_port: 8086
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
當完成上述步驟後，就可以在任一台`Master`節點進行操作 Kubernetes：
```sh
$ kubectl get po -n kube-system
NAME                              READY     STATUS    RESTARTS   AGE
haproxy-master1                   1/1       Running   0           3m
haproxy-master2                   1/1       Running   0           3m
haproxy-master3                   1/1       Running   0           3m
keepalived-master1                1/1       Running   0           3m
keepalived-master2                1/1       Running   0           3m
keepalived-master3                1/1       Running   0           3m
kube-apiserver-master1            1/1       Running   0           2m
kube-apiserver-master2            1/1       Running   0           2m
kube-apiserver-master3            1/1       Running   0           2m
kube-controller-manager-master1   1/1       Running   0           2m
kube-controller-manager-master2   1/1       Running   0           2m
kube-controller-manager-master3   1/1       Running   0           2m
kube-dashboard-3349010116-8fxk4   1/1       Running   0           5m
kube-dns-1q50g                    3/3       Running   0           6m
kube-proxy-amd64-51scn            1/1       Running   0           4m
kube-proxy-amd64-gbkhd            1/1       Running   0           4m
kube-proxy-amd64-s23md            1/1       Running   0           4m
kube-proxy-amd64-vmd6t            1/1       Running   0           4m
kube-proxy-amd64-5cs1n            1/1       Running   0           4m
kube-proxy-amd64-adgcd            1/1       Running   0           4m
kube-proxy-amd64-6vacz            1/1       Running   0           4m
kube-proxy-amd64-9jkca            1/1       Running   0           4m
kube-scheduler-master1            1/1       Running   0           2m
kube-scheduler-master2            1/1       Running   0           2m
kube-scheduler-master3            1/1       Running   0           2m
```
> 確認都是`Running`後，就可以進入 [Dashboard](http://172.20.3.90)。

接著透過 Etcd 來查看目前 Leader 狀態：
```sh
$ etcdctl member list
2de3b0eee054a36f: name=master1 peerURLs=http://172.20.3.91:2380 clientURLs=http://172.20.3.91:2379 isLeader=false
75809e2ee8d8d4b4: name=master2 peerURLs=http://172.20.3.92:2380 clientURLs=http://172.20.3.92:2379 isLeader=false
af31edd02fc70872: name=master3 peerURLs=http://172.20.3.93:2380 clientURLs=http://172.20.3.93:2379 isLeader=true
```
