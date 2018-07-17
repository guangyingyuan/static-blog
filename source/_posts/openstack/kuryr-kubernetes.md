---
title: 利用 Kuryr 整合 OpenStack 與 Kubernetes 網路
catalog: true
date: 2017-08-29 16:23:01
categories:
- OpenStack
tags:
- OpenStack
- Kubernetes
- Docker
---
[Kubernetes Kuryr](https://github.com/openstack/kuryr-kubernetes) 是 OpenStack Neutron 的子專案，其主要目標是透過該專案來整合 OpenStack 與 Kubernetes 的網路。該專案在 Kubernetes 中實作了原生 Neutron-based 的網路，因此使用 Kuryr-Kubernetes 可以讓你的 OpenStack VM 與 Kubernetes Pods 能夠選擇在同一個子網路上運作，並且能夠使用 Neutron 的 L3 與 Security Group 來對網路進行路由，以及阻擋特定來源 Port。

![](https://i.imgur.com/2XfP3vb.png)

<!--more-->

Kuryr-Kubernetes 整合有兩個主要組成部分：
1. **Kuryr Controller**:
Controller 主要目的是監控 Kubernetes API 的來獲取 Kubernetes 資源的變化，然後依據 Kubernetes 資源的需求來執行子資源的分配和資源管理。
2. **Kuryr CNI**：主要是依據 Kuryr Controller 分配的資源來綁定網路至 Pods 上。

本篇我們將說明如何利用`DevStack`與`Kubespray`建立一個簡單的測試環境。

## 環境資源與事前準備
準備兩台實體機器，這邊測試的作業系統為`CentOS 7.x`，該環境將在扁平的網路下進行。

| IP Address 1    |  Role      |
| --------        | --------   |
| 172.24.0.34     | controller, k8s-master |
| 172.24.0.80     | compute, k8s-node1 |

更新每台節點的 CentOS 7.x packages:
```shell=
$ sudo yum --enablerepo=cr update -y
```

然後關閉 firewalld 以及 SELinux 來避免實現發生問題：
```shell=
$ sudo setenforce 0
$ sudo systemctl disable firewalld && sudo systemctl stop firewalld
```

## OpenStack Controller 安裝
首先進入`172.24.0.34（controller）`，並且執行以下指令。

然後執行以下指令來建立 DevStack 專用使用者：
```shell=
$ sudo useradd -s /bin/bash -d /opt/stack -m stack
$ echo "stack ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/stack
```
> 選用 DevStack 是因為現在都是用 Systemd 來管理服務，不用再用 screen 了，雖然都很方便。

接著切換至該使用者環境來建立 OpenStack：
```shell=
$ sudo su - stack
```

下載 DevStack 安裝套件：
```shell=
$ git clone https://git.openstack.org/openstack-dev/devstack
$ cd devstack
```

新增`local.conf`檔案，來描述部署資訊：
```
[[local|localrc]]
HOST_IP=172.24.0.34
GIT_BASE=https://github.com

ADMIN_PASSWORD=passwd
DATABASE_PASSWORD=passwd
RABBIT_PASSWORD=passwd
SERVICE_PASSWORD=passwd
SERVICE_TOKEN=passwd
MULTI_HOST=1
```
> [color=#fc9fca]Tips:
> 修改 HOST_IP 為自己的 IP 位置。

完成後，執行以下指令開始部署：
```shell=
$ ./stack.sh
```


## Openstack Compute 安裝
進入到`172.24.0.80（compute）`，並且執行以下指令。

然後執行以下指令來建立 DevStack 專用使用者：
```shell=
$ sudo useradd -s /bin/bash -d /opt/stack -m stack
$ echo "stack ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/stack
```
> 選用 DevStack 是因為現在都是用 Systemd 來管理服務，不用再用 screen 了，雖然都很方便。

接著切換至該使用者環境來建立 OpenStack：
```shell=
$ sudo su - stack
```

下載 DevStack 安裝套件：
```shell=
$ git clone https://git.openstack.org/openstack-dev/devstack
$ cd devstack
```

新增`local.conf`檔案，來描述部署資訊：
```
[[local|localrc]]
HOST_IP=172.24.0.80
GIT_BASE=https://github.com
MULTI_HOST=1
LOGFILE=/opt/stack/logs/stack.sh.log
ADMIN_PASSWORD=passwd
DATABASE_PASSWORD=passwd
RABBIT_PASSWORD=passwd
SERVICE_PASSWORD=passwd
DATABASE_TYPE=mysql

SERVICE_HOST=172.24.0.34
MYSQL_HOST=$SERVICE_HOST
RABBIT_HOST=$SERVICE_HOST
GLANCE_HOSTPORT=$SERVICE_HOST:9292
ENABLED_SERVICES=n-cpu,q-agt,n-api-meta,c-vol,placement-client
NOVA_VNC_ENABLED=True
NOVNCPROXY_URL="http://$SERVICE_HOST:6080/vnc_auto.html"
VNCSERVER_LISTEN=$HOST_IP
VNCSERVER_PROXYCLIENT_ADDRESS=$VNCSERVER_LISTEN
```
> Tips:
> 修改 HOST_IP 為自己的主機位置。
> 修改 SERVICE_HOST 為 Master 的IP位置。

完成後，執行以下指令開始部署：
```shell=
$ ./stack.sh
```

## 建立 Kubernetes 叢集環境
首先確認所有節點之間不需要 SSH 密碼即可登入，接著進入到`172.24.0.34（k8s-master）`並且執行以下指令。

接著安裝所需要的套件：
```shell=
$ sudo yum -y install software-properties-common ansible git gcc python-pip python-devel libffi-devel openssl-devel
$ sudo pip install -U kubespray
```

完成後，新增 kubespray 設定檔：
```shell=
$ cat <<EOF >  ~/.kubespray.yml
kubespray_git_repo: "https://github.com/kubernetes-incubator/kubespray.git"
# Logging options
loglevel: "info"
EOF
```

然後利用 kubespray-cli 快速產生環境的`inventory`檔，並修改部分內容：
```shell=
$ sudo -i
$ kubespray prepare --masters master --etcds master --nodes node1
```

編輯`/root/.kubespray/inventory/inventory.cfg`，修改以下內容：
```
[all]
master  ansible_host=172.24.0.34 ansible_user=root ip=172.24.0.34
node1    ansible_host=172.24.0.80 ansible_user=root ip=172.24.0.80

[kube-master]
master

[kube-node]
master
node1

[etcd]
master

[k8s-cluster:children]
kube-node1
kube-master
```

完成後，即可利用 kubespray-cli 指令來進行部署：
```shell=
$ kubespray deploy --verbose -u root -k .ssh/id_rsa -n calico
```

經過一段時間後就會部署完成，這時候檢查節點是否正常：
```shell=
$ kubectl get no
NAME      STATUS         AGE       VERSION
master    Ready,master   2m        v1.7.4
node1     Ready          2m        v1.7.4
```

接著為了方便讓 Kuryr Controller 簡單取得 K8s API Server，這邊修改`/etc/kubernetes/manifests/kube-apiserver.yml`檔案，加入以下內容：
```
- "--insecure-bind-address=0.0.0.0"
- "--insecure-port=8080"
```
> Tips:
> 將 insecure 綁定到 0.0.0.0 之上，以及開啟 8080 Port。


## 安裝 Openstack Kuryr
進入到`172.24.0.34（controller）`，並且執行以下指令。

首先在節點安裝所需要的套件：
```shell=
$ sudo yum -y install  gcc libffi-devel python-devel openssl-devel install python-pip
```

然後下載 kuryr-kubernetes 並進行安裝：
```shell=
$ git clone http://git.openstack.org/openstack/kuryr-kubernetes
$ pip install -e kuryr-kubernetes
```

新增`kuryr.conf`至`/etc/kuryr`目錄：
```shell=
$ cd kuryr-kubernetes
$ ./tools/generate_config_file_samples.sh
$ sudo mkdir -p /etc/kuryr/
$ sudo cp etc/kuryr.conf.sample /etc/kuryr/kuryr.conf
```

接著使用 OpenStack Dashboard 建立相關專案，在瀏覽器輸入[Dashboard](http://172.24.0.34)，並執行以下步驟。

1. 新增 K8s project。
2. 修改 K8s project member 加入到 service project。
3. 在該 Project 中新增 Security Groups，參考 [kuryr-kubernetes manually](https://docs.openstack.org/kuryr-kubernetes/latest/installation/manual.html)。
4. 在該 Project 中新增 pod_subnet 子網路。
5. 在該 Project 中新增 service_subnet 子網路。


完成後，修改`/etc/kuryr/kuryr.conf`檔案，加入以下內容：
```
[DEFAULT]
use_stderr = true
bindir = /usr/local/libexec/kuryr

[kubernetes]
api_root = http://172.24.0.34:8080

[neutron]
auth_url = http://172.24.0.34/identity
username = admin
user_domain_name = Default
password = admin
project_name = service
project_domain_name = Default
auth_type = password

[neutron_defaults]
ovs_bridge = br-int
pod_security_groups = {id_of_secuirity_group_for_pods}
pod_subnet = {id_of_subnet_for_pods}
project = {id_of_project}
service_subnet = {id_of_subnet_for_k8s_services}
```

完成後執行 kuryr-k8s-controller：
```shell=
$ kuryr-k8s-controller --config-file /etc/kuryr/kuryr.conf
```

## 安裝 Kuryr-CNI
進入到`172.24.0.80（node1）`並且執行以下指令。

首先在節點安裝所需要的套件：
```shell=
$ sudo yum -y install  gcc libffi-devel python-devel openssl-devel python-pip
```

然後安裝 Kuryr-CNI 來提供給 kubelet 使用：
```shell=
$ git clone http://git.openstack.org/openstack/kuryr-kubernetes
$ sudo pip install -e kuryr-kubernetes
```

新增`kuryr.conf`至`/etc/kuryr`目錄：
```shell=
$ cd kuryr-kubernetes
$ ./tools/generate_config_file_samples.sh
$ sudo mkdir -p /etc/kuryr/
$ sudo cp etc/kuryr.conf.sample /etc/kuryr/kuryr.conf
```

修改`/etc/kuryr/kuryr.conf`檔案，加入以下內容：
```
[DEFAULT]
use_stderr = true
bindir = /usr/local/libexec/kuryr
[kubernetes]
api_root = http://172.24.0.34:8080
```

建立 CNI bin 與 Conf 目錄：
```shell=
$ sudo mkdir -p /opt/cni/bin
$ sudo ln -s $(which kuryr-cni) /opt/cni/bin/
$ sudo mkdir -p /etc/cni/net.d/
```

新增`/etc/cni/net.d/10-kuryr.conf` CNI 設定檔：
```
{
    "cniVersion": "0.3.0",
    "name": "kuryr",
    "type": "kuryr-cni",
    "kuryr_conf": "/etc/kuryr/kuryr.conf",
    "debug": true
}
```

完成後，更新 oslo 與 vif python 函式庫：
```shell=
$ sudo pip install 'oslo.privsep>=1.20.0' 'os-vif>=1.5.0'
```

最後重新啟動相關服務：
```shell=
$ sudo systemctl daemon-reload && systemctl restart kubelet.service
```

## 測試結果
我們這邊開一個 Pod 與 OpenStack VM 來進行溝通：
![](https://i.imgur.com/UYXdKud.png)

![](https://i.imgur.com/dwoEytW.png)
