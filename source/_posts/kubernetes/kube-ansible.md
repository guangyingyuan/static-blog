---
title: 使用 kube-ansible 快速部署 HA 測試環境
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

<!--more-->

kube-ansible 提供了以下幾項功能：
* Vagrant scripts.
* Kubernetes cluster setup(v1.5.0+).
* Kubernetes addons.
    * Dashboard
    * Kube-DNS
    * Monitor
    * Kube-Proxy
* Kubernetes High Availability.
* Ceph cluster on Kubernetes(v11.2.0+).

而在 OS 部分以支援`Ubuntu 16.x`及`CentOS 7.x`的虛擬機與實體機部署。未來會以 Python 工具形式來提供使用。

## 快速開始
kube-ansible 支援了 Vagrant 腳本來快速提供 VirtualBox 環境，若想單一主機模擬 Kubernetes 叢集的話，主機需要安裝以下軟體工具：
* Vagrant >= 1.7.0
* VirtualBox >= 5.0.0

當主機確認安裝完成後，即可透過 Git 下載最新版本程式，並使用`setup-vagrant`腳本：
```sh
$ git clone "https://github.com/kairen/kube-ansible.git"
$ ./setup-vagrant -h
Usage : setup-vagrant [options]

 -b|--boss        This option is launch master count.
 -n|--node        This option is launch node count.
 -c|--cpu         This option is vbox vcpu.
 -m|--memory      This option is vbox memory.
```

這邊執行以下指令來建立三台 Master 與三台 Node 的環境：
```sh
$ ./setup-vagrant --boss 3 --node 3
```
> 預設 CPU 為 1vCPU，而 Memory 為 1024MB。

執行後需要等一點時間，當完成後就可以進入任何一台 Master 進行操作：
```sh
$ kubectl get node
NAME      STATUS            AGE
master1   Ready,master      1m
master2   Ready,master      1m
master3   Ready,master      1m
node1     Ready             1m
node2     Ready             1m
node3     Ready             1m
```

確認節點沒問題後就可以查看 Pod 狀態：
```sh
$ kubectl get po --all-namespaces -o wide
NAMESPACE     NAME                                    READY     STATUS    RESTARTS   AGE       IP             NODE
kube-system   haproxy-master1                         1/1       Running   0          6m        172.16.35.13   master1
kube-system   haproxy-master2                         1/1       Running   1          3m        172.16.35.14   master2
kube-system   haproxy-master3                         1/1       Running   0          6m        172.16.35.15   master3
kube-system   kube-apiserver-master1                  1/1       Running   0          6m        172.16.35.13   master1
kube-system   kube-apiserver-master2                  1/1       Running   1          3m        172.16.35.14   master2
kube-system   kube-apiserver-master3                  1/1       Running   0          5m        172.16.35.15   master3
kube-system   kube-controller-manager-master1         1/1       Running   0          6m        172.16.35.13   master1
kube-system   kube-controller-manager-master2         1/1       Running   1          3m        172.16.35.14   master2
kube-system   kube-controller-manager-master3         1/1       Running   0          6m        172.16.35.15   master3
kube-system   kube-dns-v20-0wkl3                      3/3       Running   0          6m        172.20.8.2     node3
kube-system   kube-proxy-amd64-5dlqg                  1/1       Running   0          6m        172.16.35.14   master2
kube-system   kube-proxy-amd64-f20xg                  1/1       Running   0          6m        172.16.35.10   node1
kube-system   kube-proxy-amd64-g095q                  1/1       Running   0          6m        172.16.35.13   master1
kube-system   kube-proxy-amd64-kf2d9                  1/1       Running   0          6m        172.16.35.12   node3
kube-system   kube-proxy-amd64-r180j                  1/1       Running   0          6m        172.16.35.15   master3
kube-system   kube-proxy-amd64-r9sk0                  1/1       Running   0          6m        172.16.35.11   node2
kube-system   kube-scheduler-master1                  1/1       Running   0          6m        172.16.35.13   master1
kube-system   kube-scheduler-master2                  1/1       Running   1          3m        172.16.35.14   master2
kube-system   kube-scheduler-master3                  1/1       Running   1          5m        172.16.35.15   master3
kube-system   kubernetes-dashboard-3697905830-bnvfd   1/1       Running   0          6m        172.20.85.2    node1
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

## 驗證 Master HA 功能
最後我們針對 Kubernetes Master HA 進行功能驗證，首先我們先取得目前 kube-scheduler 與 kube-controller-manager 的 Leader：
```sh
$ etcdctl member list
2de3b0eee054a36f: name=master1 peerURLs=http://172.16.35.13:2380 clientURLs=http://172.16.35.13:2379 isLeader=false
75809e2ee8d8d4b4: name=master2 peerURLs=http://172.16.35.14:2380 clientURLs=http://172.16.35.14:2379 isLeader=false
af31edd02fc70872: name=master3 peerURLs=http://172.16.35.15:2380 clientURLs=http://172.16.35.15:2379 isLeader=true
```
> 這邊可以看到 master3 為 Leader。

當確認 Leader 後，即可關閉該節點進行測試，進入到其他 master:
```sh
master3# sudo poweroff
master1# etcdctl member list
2de3b0eee054a36f: name=master1 peerURLs=http://172.16.35.13:2380 clientURLs=http://172.16.35.13:2379 isLeader=true
75809e2ee8d8d4b4: name=master2 peerURLs=http://172.16.35.14:2380 clientURLs=http://172.16.35.14:2379 isLeader=false
af31edd02fc70872: name=master3 peerURLs=http://172.16.35.15:2380 clientURLs=http://172.16.35.15:2379 isLeader=false

master1# kubectl get node
NAME      STATUS            AGE
master1   Ready,master      1h
master2   Ready,master      1h
master3   NotReady,master   1h
node1     Ready             1h
node2     Ready             1h
node3     Ready             1h
```

上面可以看到 master3 已經掛掉，並且 Leader 已經換人了，這邊可以進一步操作 Kubernetes 其他指令來驗證。最後若在關閉一台將會發生 Etcd 叢集錯誤，造成 Kubernetes 功能無法正常。
