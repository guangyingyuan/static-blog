---
title: 開發 Ansible Playbooks 部署 Kubernetes v1.11.x HA 叢集
date: 2018-08-12 17:08:54
catalog: true
header-img: /images/kube/bg.png
categories:
- Kubernetes
tags:
- Ansible
- Kubernetes
- Docker
---
本篇將介紹如何透過 Ansible Playbooks 來快速部署多節點 Kubernetes，一般自建 Kubernetes 叢集時，很多初步入門都會透過 kubeadm 或腳本來部署，雖然 kubeadm 簡化了很多流程，但是還是需要很多手動操作過程，這使得當節點超過 5 - 8 台時就覺得很麻煩，因此許多人會撰寫腳本來解決這個問題，但是腳本的靈活性不佳，一旦設定過程過於龐大時也會造成其複雜性增加，因此這邊採用 Ansible 來完成許多重複的部署過程，並提供相關變數來調整叢集部署的元件、Container Runtime 等等。

這邊我將利用自己撰寫的 [kube-ansible](https://github.com/kairen/kube-ansible) 來部署一組 Kubernetes HA 叢集，而該 Playbooks 的 HA 是透過 HAProxy + Keepalived 來完成，這邊也會將 docker 取代成 containerd 來提供更輕量的 container runtime，另外該 Ansible 會採用全二進制檔案(kube-apiserver 等除外)方式進行安裝。

本次 Kubernetes 安裝版本：
* Kubernetes v1.11.2
* Etcd v3.2.9
* containerd v1.1.2

<!--more-->

## 節點資訊
本次安裝作業系統採用`Ubuntu 16+`，測試環境為實體主機：

| IP Address  |   Role   | CPU | Memory |
|-------------|----------|-----|--------|
|172.22.132.8 |  VIP     |     |        |
|172.22.132.9 |  k8s-m1  | 4   | 16G    |
|172.22.132.10|  k8s-m2  | 4   | 16G    |
|172.22.132.11|  k8s-m3  | 4   | 16G    |
|172.22.132.12|  k8s-g1  | 4   | 16G    |
|172.22.132.13|  k8s-g2  | 4   | 16G    |

> 理論上`CentOS 7.x`或`Debian 8`都可以。

## 事前準備
安裝前需要確認以下幾個項目：
* 所有節點的網路之間可以互相溝通。
* `部署節點`對其他節點不需要 SSH 密碼即可登入。
* 所有節點都擁有 Sudoer 權限，並且不需要輸入密碼。
* 所有節點需要安裝 `Python`。
* 所有節點需要設定`/etc/host`解析到所有主機。
* `部署節點`需要安裝 Ansible。

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

Mac OS X 安裝 Ansible:
```sh
$ brew install ansible
```

## 透過 Ansible 部署 Kubernetes
本節將說明如何使用 Ansible 來部署 Kubernetes HA 叢集，首先我們透過 Git 取得專案:
```sh
$ git clone https://github.com/kairen/kube-ansible.git
$ cd kube-ansible
```

### Kubernetes 叢集
首先建立一個檔案`inventory/hosts.ini`來描述被部署的節點與群組關析：
```
[etcds]
k8s-m[1:3] ansible_user=ubuntu

[masters]
k8s-m[1:3] ansible_user=ubuntu

[nodes]
k8s-g1 ansible_user=ubuntu
k8s-g2 ansible_user=ubuntu

[kube-cluster:children]
masters
nodes
```
> `ansible_user`為作業系統 SSH 的使用者名稱。

接著編輯`group_vars/all.yml`來根據需求設定功能，如以下範例：
```yaml

kube_version: 1.11.2

container_runtime: containerd

cni_enable: true
container_network: calico
cni_iface: "" # CNI 網路綁定的網卡

vip_interface: "" # VIP 綁定的網卡
vip_address: 172.22.132.8 # VIP 位址

etcd_iface: "" # etcd 綁定的網卡

enable_ingress: true
enable_dashboard: true
enable_logging: true
enable_monitoring: true
enable_metric_server: true

grafana_user: "admin"
grafana_password: "p@ssw0rd"
```
> 上面綁定網卡若沒有輸入，通常會使用節點預設網卡(一般來說是第一張網卡)。

完成設定`group_vars/all.yml`檔案後，就可以先透過 Ansible 來檢查叢集狀態：
```sh
$ ansible -i inventory/hosts.ini all -m ping
k8s-g1 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
...
```

當叢集確認沒有問題後，即可執行`cluster.yml`來部署 Kubernetes 叢集：
```sh
$ ansible-playbook -i inventory/hosts.ini cluster.yml
...
PLAY RECAP ***********************************************************************************************************************
k8s-g1                     : ok=64   changed=32   unreachable=0    failed=0
k8s-g2                     : ok=62   changed=32   unreachable=0    failed=0
k8s-m1                     : ok=171  changed=85   unreachable=0    failed=0
k8s-m2                     : ok=144  changed=69   unreachable=0    failed=0
k8s-m3                     : ok=144  changed=69   unreachable=0    failed=0
```
> 確認都沒發生錯誤後，表示部署完成。

這邊選擇一台 master 節點(`k8s-m1`)來 SSH 進入測試叢集是否正常，透過 kubectl 指令來查看：
```sh
# 查看元件狀態
$ kubectl get cs
NAME                 STATUS    MESSAGE              ERROR
controller-manager   Healthy   ok
scheduler            Healthy   ok
etcd-1               Healthy   {"health": "true"}
etcd-2               Healthy   {"health": "true"}
etcd-0               Healthy   {"health": "true"}

# 查看節點狀態
$ kubectl get no
NAME      STATUS    ROLES     AGE       VERSION
k8s-g1    Ready     <none>    3m        v1.11.2
k8s-g2    Ready     <none>    3m        v1.11.2
k8s-m1    Ready     master    5m        v1.11.2
k8s-m2    Ready     master    5m        v1.11.2
k8s-m3    Ready     master    5m        v1.11.2
```

### Addons 部署
確認節點沒問題後，就可以透過`addons.yml`來部署 Kubernetes extra addons：
```sh
$ ansible-playbook -i inventory/hosts.ini addons.yml
...
PLAY RECAP ***********************************************************************************************************************
k8s-m1                     : ok=27   changed=22   unreachable=0    failed=0
k8s-m2                     : ok=10   changed=5    unreachable=0    failed=0
k8s-m3                     : ok=10   changed=5    unreachable=0    failed=0
```

完成後即可透過 kubectl 來檢查服務，如 kubernetes-dashboard：
```sh
$ kubectl get po,svc -n kube-system -l k8s-app=kubernetes-dashboard
NAME                                       READY     STATUS    RESTARTS   AGE
pod/kubernetes-dashboard-6948bdb78-bkqbr   1/1       Running   0          32m

NAME                           TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
service/kubernetes-dashboard   ClusterIP   10.105.199.72   <none>        443/TCP   32m
```

完成後，即可透過 API Server 的 Proxy 來存取 https://172.22.132.8:8443/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/。

![](https://i.imgur.com/G3g4LLo.png)

## 測試是否有 HA
首先透過 etcdctl 來檢查狀態：
```sh
$ export PKI="/etc/kubernetes/pki/etcd"
$ ETCDCTL_API=3 etcdctl \
    --cacert=${PKI}/etcd-ca.pem \
    --cert=${PKI}/etcd.pem \
    --key=${PKI}/etcd-key.pem \
    --endpoints="https://172.22.132.9:2379" \
    member list

c9c9f1e905ce83ae, started, k8s-m1, https://172.22.132.9:2380, https://172.22.132.9:2379
cb81b1446a3a689f, started, k8s-m3, https://172.22.132.11:2380, https://172.22.132.11:2379
db0b2674ebb24f80, started, k8s-m2, https://172.22.132.10:2380, https://172.22.132.10:2379
```

接著進入`k8s-m1`節點測試叢集 HA 功能，這邊先關閉該節點：
```sh
$ sudo poweroff
```

接著進入到`k8s-m2`節點，透過 kubectl 來檢查叢集是否能夠正常執行：
```sh
# 先檢查元件狀態
$ kubectl get cs
NAME                 STATUS      MESSAGE                                                                                                                                          ERROR
controller-manager   Healthy     ok
scheduler            Healthy     ok
etcd-2               Healthy     {"health": "true"}
etcd-1               Healthy     {"health": "true"}
etcd-0               Unhealthy   Get https://172.22.132.9:2379/health: net/http: request canceled while waiting for connection (Client.Timeout exceeded while awaiting headers)

# 檢查 nodes 狀態
$ kubectl get no
NAME      STATUS     ROLES     AGE       VERSION
k8s-g1    Ready      <none>    10m       v1.11.2
k8s-g2    Ready      <none>    10m       v1.11.2
k8s-m1    NotReady   master    12m       v1.11.2
k8s-m2    Ready      master    12m       v1.11.2
k8s-m3    Ready      master    12m       v1.11.2

# 測試是否可以建立 Pod
$ kubectl run nginx --image nginx --restart=Never --port 80
$ kubectl expose pod nginx --port 80 --type NodePort
$ kubectl get po,svc
NAME        READY     STATUS    RESTARTS   AGE
pod/nginx   1/1       Running   0          1m

NAME                 TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)        AGE
service/kubernetes   ClusterIP   10.96.0.1        <none>        443/TCP        3h
service/nginx        NodePort    10.102.191.102   <none>        80:31780/TCP   6s
```

透過 cURL 檢查 NGINX 服務是否正常：
```sh
$ curl 172.22.132.8:31780
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
...
```

## 重置叢集
最後若想要重新部署叢集的話，可以透過`reset-cluster.yml`來清除叢集：
```sh
$ ansible-playbook -i inventory/hosts.ini reset-cluster.yml
```
