---
title: Vagrant CoreOS 部署 Kubernetes 測試叢集(Unrecommended)
date: 2016-2-23 17:08:54
catalog: true
categories:
- Kubernetes
tags:
- Kubernetes
- Docker
- CoreOS
- Vagrant
---
本節將透過 Vagrant 與 CoreOS 來部署單機多節點的 Kubernetes 虛擬叢集，並使用 Kubernetest CLI 工具與 API 進行溝通。

本次安裝版本為：
* CoreOS alpha.
* Kubernetes v1.5.4.

<!--more-->

## 事前準備
首先必須在主機上安裝`Vagrant`工具，點選該 [Vagrant downloads](https://www.vagrantup.com/downloads.html) 頁面抓取當前系統的版本，並完成安裝。

接著在主機上安裝`kubectl`，該程式是主要與 Kubernetes API 進行溝通的工具，透過 Curl 工具來下載。如果是 Linux 作業系統，請下載以下：
```sh
$ curl -O "https://storage.googleapis.com/kubernetes-release/release/v1.5.4/bin/linux/amd64/kubectl"
$ chmod +x kubectl && sudo mv kubectl /usr/local/bin/
```
> 如果是 OS X，請取代 URL 為以下：
```sh
$ curl -O "https://storage.googleapis.com/kubernetes-release/release/v1.5.4/bin/darwin/amd64/kubectl"
$ chmod +x kubectl && sudo mv kubectl /usr/local/bin/
```

## 安裝 Kubernetes
首先透過 Git 工具來下載 CoreOS 的 Kubernetes 專案，裡面包含了描述 Vagrant 要建立的檔案：
```sh
$ git clone https://github.com/coreos/coreos-kubernetes.git
$ cd coreos-kubernetes/multi-node/vagrant
```

接著複製`config.rb.sample`並改成`config.rb`檔案：
```sh
$ cp config.rb.sample config.rb
```

編輯`config.rb`設定檔，並修改成以下內容：
```ruby
$update_channel="alpha"

$controller_count=1
$controller_vm_memory=1024

$worker_count=2
$worker_vm_memory=1024

$etcd_count=1
$etcd_vm_memory=512
```

(Option)若 CNI 想使用 Calico 網路與安裝不同版本 Kubernetes 的話，需要修改`../generic/controller-install.sh`與`./generic/worker-install.sh`檔案以下內容：
```sh
export K8S_VER=v1.5.4_coreos.0
export USE_CALICO=true
```

設定好後，即可透過以下指令來建立 SSL CA Key 與更新 Box 資訊：
```sh
$ sudo ln -sf /usr/local/bin/openssl /opt/vagrant/embedded/bin/openssl
$ vagrant box update
```

確認完成後，執行以下指令開始建立叢集：
```sh
$ vagrant up
```
> P.S. 這邊建置起來裡面虛擬機還要下載一些東西，要等一下子才會真正完成。

## 設定 Kubernetes Config
當完成部署後，需要配置 kubectl 連接 API，這邊可以選擇以下兩種的其中一種進行：

### 使用一個 Custom Kubernetes Config
```sh
$ export KUBECONFIG="${KUBECONFIG}:$(pwd)/kubeconfig"
$ kubectl config use-context vagrant-multi
```

### 更新與使用本地的 Config
```sh
$ kubectl config set-cluster vagrant-multi-cluster --server="https://172.17.4.101:443" --certificate-authority=${PWD}/ssl/ca.pem
$ kubectl config set-credentials vagrant-multi-admin --certificate-authority=${PWD}/ssl/ca.pem --client-key=${PWD}/ssl/admin-key.pem --client-certificate=${PWD}/ssl/admin.pem
$ kubectl config set-context vagrant-multi --cluster=vagrant-multi-cluster --user=vagrant-multi-admin
$ kubectl config use-context vagrant-multi
```

## Kubernetes 系統驗證
完成設定後，即可使用 kubectl 來查看節點資訊：
```sh
$ kubectl get nodes
NAME           STATUS                     AGE
172.17.4.101   Ready,SchedulingDisabled   3m
172.17.4.201   Ready                      3m
172.17.4.202   Ready                      3m
```

查看系統命名空間的 pod 與 svc 資訊：
```sh
$ kubectl get po --all-namespaces
NAMESPACE     NAME                                    READY     STATUS    RESTARTS   AGE
kube-system   heapster-v1.2.0-4088228293-4vv12        2/2       Running   0          28m
kube-system   kube-apiserver-172.17.4.101             1/1       Running   0          29m
kube-system   kube-controller-manager-172.17.4.101    1/1       Running   0          29m
kube-system   kube-dns-782804071-w6w12                4/4       Running   0          29m
kube-system   kube-dns-autoscaler-2715466192-q1k18    1/1       Running   0          29m
kube-system   kube-proxy-172.17.4.101                 1/1       Running   0          28m
kube-system   kube-proxy-172.17.4.201                 1/1       Running   0          29m
kube-system   kube-proxy-172.17.4.202                 1/1       Running   0          29m
kube-system   kube-scheduler-172.17.4.101             1/1       Running   0          28m
kube-system   kubernetes-dashboard-3543765157-vk0mt   1/1       Running   0          29m
```
