---
title: 利用 Minikube 快速建立測試用 Kubernetes 叢集
subtitle: ""
date: 2019-1-22 17:08:54
catalog: true
header-img: /images/kube/bg.png
categories:
- Kubernetes
tags:
- Kubernetes
- Docker
- Calico
---
本文將說明如何透過 Minikube 建立多節點 Kubernetes 叢集。一般來說 Minikube 僅提供單節點功能，即透過虛擬機建立僅有一個具備 Master/Node 節點的 Kubernetes 叢集，但由時候需要測試多節點功能，因此自己改了一下 Minikube 來支援最新版本(v1.13.2)的多節點部署，且 CNI Plugin 採用 Calico，以方便測試 Network Policy 功能。

![](/images/kube/minikube-logo.jpg)

<!--more-->

## 事前準備
開始部署叢集前需先確保以下條件已達成：

* 在測試機器下載 Minikube 二進制執行檔：
    * [Linux](https://github.com/kairen/minikube/releases/download/v0.33.1-multi-node/minikube-linux-amd64)
    * [Mac OS X](https://github.com/kairen/minikube/releases/download/v0.33.1-multi-node/minikube-darwin-amd64)
    * [Windows](https://github.com/kairen/minikube/releases/download/v0.33.1-multi-node/minikube-windows-amd64.exe)

{% colorquote warning %}
如果上面連結掛了，可以透過以下方式安裝：
```bash
$ git clone https://github.com/kairen/minikube.git -b multi-node $GOPATH/src/k8s.io/minikube
$ cd $GOPATH/src/k8s.io/minikube
$ make
```
{% endcolorquote %}

* 在測試機器下載 [Virtual Box](https://www.virtualbox.org/wiki/Downloads) 來提供給 Minikube 建立虛擬機。

{% colorquote warning %}
* **IMPORTANT**: 測試機器記得開啟 VT-x or AMD-v virtualization.
* 雖然建議用 VBox，但是討厭 Oracle 的人可以改用其他虛擬化工具(ex: KVM, xhyve)，理論上可以動。
{% endcolorquote %}

* 下載所屬作業系統的 [kubeclt](https://kubernetes.io/docs/tasks/tools/install-kubectl/)。

{% colorquote info %}
* 目前已測試過 Ubuntu 16.04 Desktop、Mac OS X 與 Windows 10 作業系統。
* Windows 使用者建議用 git bash 來操作。
{% endcolorquote %}

## 建立叢集
本節將說明如何建立 Master 與 Node 節點，並將這些節點組成一個叢集。

在開始前確認之前是否已經裝過 Minikube，若有的話，就把上面下載二進制檔放任意方便你執行的位置，或者直接取代之前的，然後再開始前請先刪除 Home 目錄的`.minikube`資料夾：
```bash
$ rm -rf $HOME/.minikube
```

### Master 節點
首先透過 Minikube 執行以下指令來啟動 Master 節點，並透過 kubectl 檢查：
```bash
$ minikube --profile k8s-m1 start --network-plugin=cni
...
Everything looks great. Please enjoy minikube!

$ kubectl -n kube-system get po -o wide
NAME                             READY   STATUS    RESTARTS   AGE     IP               NODE     NOMINATED NODE   READINESS GATES
calico-node-8cbc6                2/2     Running   0          6m29s   192.168.99.100   k8s-m1   <none>           <none>
coredns-86c58d9df4-4nzlx         1/1     Running   0          6m32s   10.244.0.3       k8s-m1   <none>           <none>
coredns-86c58d9df4-9879v         1/1     Running   0          6m32s   10.244.0.2       k8s-m1   <none>           <none>
etcd-k8s-m1                      1/1     Running   0          5m58s   192.168.99.100   k8s-m1   <none>           <none>
kube-addon-manager-k8s-m1        1/1     Running   0          5m47s   192.168.99.100   k8s-m1   <none>           <none>
kube-apiserver-k8s-m1            1/1     Running   0          5m43s   192.168.99.100   k8s-m1   <none>           <none>
kube-controller-manager-k8s-m1   1/1     Running   0          5m47s   192.168.99.100   k8s-m1   <none>           <none>
kube-proxy-qnq25                 1/1     Running   0          6m32s   192.168.99.100   k8s-m1   <none>           <none>
kube-scheduler-k8s-m1            1/1     Running   0          5m59s   192.168.99.100   k8s-m1   <none>           <none>
storage-provisioner              1/1     Running   0          6m30s   192.168.99.100   k8s-m1   <none>           <none>
```

{% colorquote warning %}
* `--vm-driver` 可以選擇使用其他 VM driver 來啟動虛擬機，如 xhyve、hyperv、hyperkit 與 kvm2 等等。
{% endcolorquote %}

完成後，確認 k8s-m1 節點處於 Ready 狀態：
```bash
$ kubectl get no
NAME     STATUS   ROLES    AGE    VERSION
k8s-m1   Ready    master   2m8s   v1.13.2
```

### Node 節點
確認 Master 完成後，這邊接著透過 Minikube 開啟新的節點來加入：
```bash
$ minikube --profile k8s-n1 start --network-plugin=cni --node
...
Stopping extra container runtimes...

# 接著取得 Master IP 與 Token
$ minikube --profile k8s-m1 ssh "ifconfig eth1"
$ minikube --profile k8s-m1 ssh "sudo kubeadm token list"

# 執行以下指令進入 k8s-n1
$ minikube --profile k8s-n1 ssh

# 這邊為進入 k8s-n1 VM 內執行的指令
$ sudo su -
$ TOKEN=7rzqkm.1goumlnntalpxvw0
$ MASTER_IP=192.168.99.100
$ kubeadm join --token ${TOKEN} ${MASTER_IP}:8443 \
    --discovery-token-unsafe-skip-ca-verification \
    --ignore-preflight-errors=Swap \
    --ignore-preflight-errors=DirAvailable--etc-kubernetes-manifests

# 看到以下結果後，即可以在 k8s-m1 context 來操作。
...
Run 'kubectl get nodes' on the master to see this node join the cluster.
```

{% colorquote warning %}
* 另外上面的 IP 有可能會不同，請確認 Master 節點 IP。
* 其他節點以此類推。
{% endcolorquote %}

完成後，透過 kubectl 檢查 Node 是否有加入叢集：
```bash
$ kubectl config use-context k8s-m1
Switched to context "k8s-m1".

$ kubectl get no
NAME     STATUS   ROLES    AGE     VERSION
k8s-m1   Ready    master   3m44s   v1.13.2
k8s-n1   Ready    <none>   80s     v1.13.2

$ kubectl get csr
NAME                                                   AGE    REQUESTOR                 CONDITION
node-csr-Ut1k5mLXpXVsyZwjn2z2-fpie9HHyTkMU7wnrjDnD3E   118s   system:bootstrap:3qeeeu   Approved,Issued

$ kubectl -n kube-system get po -o wide
NAME                             READY   STATUS    RESTARTS   AGE     IP               NODE     NOMINATED NODE   READINESS GATES
calico-node-qxkw5                2/2     Running   0          86s     192.168.99.101   k8s-n1   <none>           <none>
calico-node-srhlk                2/2     Running   0          3m24s   192.168.99.100   k8s-m1   <none>           <none>
coredns-86c58d9df4-826nz         1/1     Running   0          3m27s   10.244.0.3       k8s-m1   <none>           <none>
coredns-86c58d9df4-9z7mr         1/1     Running   0          3m27s   10.244.0.2       k8s-m1   <none>           <none>
etcd-k8s-m1                      1/1     Running   0          2m40s   192.168.99.100   k8s-m1   <none>           <none>
kube-addon-manager-k8s-m1        1/1     Running   0          3m48s   192.168.99.100   k8s-m1   <none>           <none>
kube-addon-manager-k8s-n1        1/1     Running   0          86s     192.168.99.101   k8s-n1   <none>           <none>
kube-apiserver-k8s-m1            1/1     Running   0          2m36s   192.168.99.100   k8s-m1   <none>           <none>
kube-controller-manager-k8s-m1   1/1     Running   0          2m50s   192.168.99.100   k8s-m1   <none>           <none>
kube-proxy-768w8                 1/1     Running   0          86s     192.168.99.101   k8s-n1   <none>           <none>
kube-proxy-b7ndj                 1/1     Running   0          3m27s   192.168.99.100   k8s-m1   <none>           <none>
kube-scheduler-k8s-m1            1/1     Running   0          2m46s   192.168.99.100   k8s-m1   <none>           <none>
storage-provisioner              1/1     Running   0          3m17s   192.168.99.100   k8s-m1   <none>           <none>
```

這樣一個 Kubernetes 叢集就完成了，速度快一點不到 10 分鐘就可以建立好了。

## 刪除虛擬機與檔案
最後若想清除環境的話，直接刪除虛擬機即可：
```bash
$ minikube --profile <node_name> delete
```

而檔案只要刪除 Home 目錄的`.minikube`資料夾，以及`minikube`執行檔即可。
