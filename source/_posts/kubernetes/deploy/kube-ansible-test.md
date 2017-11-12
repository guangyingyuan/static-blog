---
title: kube-ansible 快速部署 HA 測試環境
date: 2017-2-17 17:08:54
layout: page
categories:
- Kubernetes
tags:
- Kubernetes
- Docker
- Ansible
---
[kube-ansible](https://github.com/kairen/kube-ansible) 提供自動化部署 Kubernetes High Availability 叢集於虛擬機與實體機上，並且支援部署 Ceph 叢集於 Kubernetes 中提供共享式儲存系統給 Pod 應用程式使用。該專案最主要是想要快速建立測試環境來進行 Kubernetes 練習與驗證。

kube-ansible 提供了以下幾項功能：
* Kubernetes 1.7.0+.
* Ceph on Kubernetes cluster.
* Common addons.

<!--more-->

而在 OS 部分以支援`Ubuntu 16.x`及`CentOS 7.x`的虛擬機與實體機部署。未來會以 Python 工具形式來提供使用。

## 快速開始
kube-ansible 支援了 Vagrant 腳本來快速提供 VirtualBox 環境，若想單一主機模擬 Kubernetes 叢集的話，主機需要安裝以下軟體工具：
* [Vagrant](https://www.vagrantup.com/downloads.html) >= 1.7.0
* [VirtualBox](https://www.virtualbox.org/wiki/Downloads) >= 5.0.0

當主機確認安裝完成後，即可透過 Git 下載最新版本程式，並使用`setup-vagrant`腳本：
```sh
$ git clone "https://github.com/kairen/kube-ansible.git"
$ cd kube-ansible
$ ./setup-vagrant -h
Usage : setup-vagrant [options]

 -b|--boss        Number of master.
 -w|--worker      Number of worker.
 -c|--cpu         Number of cores per vm.
 -m|--memory      Memory size per vm.
 -p|--provider    Virtual machine provider(virtualbox, libvirt).
 -o|--os-image    Virtual machine operation system(ubuntu16, centos7).
 -i|--interface   Network bind interface.
 -n|--network     Container Network plugin.
 -f|--force       Force deployment.
```

這邊執行以下指令來建立三台 Master 與三台 Node 的環境：
```sh
$ ./tools/setup -m 2048 -n calico -i eth1
Cluster Size: 1 master, 2 worker.
     VM Size: 1 vCPU, 2048 MB
     VM Info: ubuntu16, virtualbox
         CNI: calico, Binding iface: eth1
Start deploying?(y):y
```

執行後需要等一點時間，當完成後就可以進入任何一台 Master 進行操作：
```sh
$ kubectl -n kube-system get po
NAME                                        READY     STATUS    RESTARTS   AGE
calico-node-657hv                           2/2       Running   0          57s
calico-node-gmd8b                           2/2       Running   0          57s
calico-node-w7nj8                           2/2       Running   0          57s
calico-policy-controller-55dfcd9c69-t8s8z   1/1       Running   0          57s
haproxy-master1                             1/1       Running   0          22s
haproxy-node2                               1/1       Running   0          1m
keepalived-master1                          1/1       Running   0          30s
keepalived-node2                            1/1       Running   0          1m
kube-apiserver-master1                      1/1       Running   0          23s
kube-apiserver-node2                        1/1       Running   0          1m
kube-controller-manager-master1             1/1       Running   0          17s
kube-controller-manager-node2               1/1       Running   0          1m
kube-dns-6cb549f55f-8mgsd                   3/3       Running   0          46s
kube-proxy-l54d7                            1/1       Running   0          1m
kube-proxy-rm4nn                            1/1       Running   0          1m
kube-proxy-tvfs7                            1/1       Running   0          1m
kube-scheduler-master1                      1/1       Running   0          39s
kube-scheduler-node2                        1/1       Running   0          1m
```

這樣一個 HA 叢集就部署完成了，可以試著將一台 Master 關閉來驗證可靠性，若 Master 是三台的話，即表示可容忍最多一台故障。

## 簡單部署 Nginx 服務
當完成部署後，可以透過簡單的應用程式部署來驗證系統是否正常運作：
```sh
$ cat <<EOF > deploy.yml
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
EOF

$ kubectl create -f deploy.yml
$ kubectl get po
NAME                     READY     STATUS    RESTARTS   AGE
nginx-4087004473-g6635   1/1       Running   0          15s
```

然後透過建置 Service 來提供外部存取 Nginx HTTP 伺服器服務：
```sh
$ cat <<EOF > service.yml
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
EOF

$ kubectl create -f service.yml
$ kubectl get svc
NAME            CLUSTER-IP        EXTERNAL-IP   PORT(S)        AGE
kubernetes      192.160.0.1       <none>        443/TCP        15m
nginx-service   192.173.165.220   <nodes>       80:30000/TCP   11s
```

由於範例使用 NodePort 的類型，所以任何一台節點都可以透過 TCP 30000 Port 來存取服務，包含 VIP 172.16.35.9 也可以存取。

最後，我們可以關閉 master1 來測試是否有 HA 效果。
