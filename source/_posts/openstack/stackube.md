---
title: 多租戶 Kubernetes 部署方案 Stackube
catalog: true
date: 2017-12-20 16:23:01
categories:
- OpenStack
tags:
- Openstack
- Kubernetes
---
[Stackube](https://github.com/openstack/stackube)是一個 Kubernetes-centric 的 OpenStack 發行版本(架構如下圖所示)，該專案結合 Kubernetes 與 OpenStack 的技術來達到真正的 Kubernetes 租戶隔離，如租戶實例採用 Frakti 來進行隔離、網路採用 Neutron OVS 達到每個 Namespace 擁有獨立的網路資源等。本篇會簡單介紹如何用 DevStack 建立測試用 Stackube。

<!--more-->

![](/images/openstack/stackube-arch.png)

> P.S. 目前 Stackube 已經不再維護，僅作為測試與研究程式碼使用。

## 節點資訊
本次安裝作業系統採用`Ubuntu 16.04 Server`，測試環境為實體機器：

| IP Address    | Host     | vCPU | RAM |
|---------------|----------|------|-----|
| 172.22.132.42 | stackube1| 8    | 32G |

## 部署 Stackube
首先新增 Devstack 使用的 User：
```sh
$ sudo useradd -s /bin/bash -d /opt/stack -m stack
$ echo "stack ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/stack
$ sudo su - stack
```

透過 Git 取得 Ocata 版本的 Devstack：
```sh
$ git clone https://git.openstack.org/openstack-dev/devstack -b stable/ocata
$ cd devstack
```

取得單節範例設定檔：
```sh
$ curl -sSL https://raw.githubusercontent.com/kairen/stackube/master/devstack/local.conf.sample -o local.conf
```

完成後即可進行安裝：
```sh
$ ./stack.sh
```

## 測試基本功能
完成後，就可以透過以下指令來引入 Kubernetes 與 OpenStack client 需要的環境變數：
```sh
$ export KUBECONFIG=/opt/stack/admin.conf
$ source /opt/stack/devstack/openrc admin admin
```

Stackube 透過 CRD 新增了一個新抽象物件 Tenant，可以直接透過 Kubernetes API 來建立一個租戶，並將該租戶與 Kubernettes namespace 做綁定：
```sh
$ cat <<EOF | kubectl create -f -
apiVersion: "stackube.kubernetes.io/v1"
kind: Tenant
metadata:
  name: test
spec:
  username: "test"
  password: "password"
EOF

$ kubectl get namespace test
NAME      STATUS    AGE
test      Active    2h

$ kubectl -n test get network test -o yaml
apiVersion: stackube.kubernetes.io/v1
kind: Network
metadata:
  clusterName: ""
  creationTimestamp: 2017-12-20T06:03:33Z
  generation: 0
  name: test
  namespace: test
  resourceVersion: "4631"
  selfLink: /apis/stackube.kubernetes.io/v1/namespaces/test/networks/test
  uid: e9aef6fa-3316-11e8-8b66-448a5bd481f0
spec:
  cidr: 10.244.0.0/16
  gateway: 10.244.0.1
  networkID: ""
status:
  state: Active
```

檢查 Neutron 網路狀況：
```sh
$ neutron net-list
+--------------------------------------+----------------------+----------------------------------+----------------------------------------------------------+
| id                                   | name                 | tenant_id                        | subnets                                                  |
+--------------------------------------+----------------------+----------------------------------+----------------------------------------------------------+
| 2a8e3b54-d76f-48a9-8380-7c2a5513b1fe | kube-test-test       | f2f25d24fd9a4616bff41b018e8725d2 | 625909a9-6abf-4661-b259-ffc625bdf681 10.244.0.0/16       |
```

> P.S. 這邊個人只是研究 Stackube CNI，故不針對其於進行測試，可自行參考 [Stackube](https://stackube.readthedocs.io/en/latest/user_guide.html)。
