---
title: 利用 kubeadm 部署 Kubernetes v1.11.x HA 叢集
subtitle: ""
date: 2018-07-17 17:08:54
catalog: true
header-img: /images/kube/bg.png
categories:
- Kubernetes
tags:
- Kubernetes
- kubeadm
- Calico
---
本篇將說明如何透過 [Kubeadm](https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm/) 來部署 Kubernetes v1.11 版本的 High Availability 叢集，而本安裝主要是參考官方文件中的 [Creating Highly Available Clusters with kubeadm](https://kubernetes.io/docs/setup/independent/high-availability/) 內容來進行，這邊將透過 HAProxy 與 Keepalived 的結合來實現控制面的 Load Balancer 與 VIP。

<!--more-->



## Kubernetes 部署資訊
Kubernetes 部署的版本資訊：

* kubeadm: v1.11.0
* Kubernetes: v1.11.0
* CNI: v0.6.0
* Etcd: v3.2.18
* Docker: v18.06.0-ce
* Flannel: v0.10.0

Kubernetes 部署的網路資訊：

* **Cluster IP CIDR**: 10.244.0.0/16
* **Service Cluster IP CIDR**: 10.96.0.0/12
* **Service DNS IP**: 10.96.0.10
* **DNS DN**: cluster.local
* **Kubernetes API VIP**: 172.22.132.9
* **Kubernetes Ingress VIP**: 172.22.132.8

## 節點資訊
本教學採用以下節點數與機器規格進行部署裸機(Bare-metal)，作業系統採用`Ubuntu 16+`(理論上 CentOS 7+ 也行)進行測試：

| IP Address  | Hostname | CPU | Memory |
|-------------|----------|-----|--------|
|172.22.132.10| k8s-m1   | 4   | 16G    |
|172.22.132.11| k8s-m2   | 4   | 16G    |
|172.22.132.12| k8s-m3   | 4   | 16G    |
|172.22.132.13| k8s-g1   | 4   | 16G    |
|172.22.132.14| k8s-g2   | 4   | 16G    |

另外由所有 master 節點提供一組 VIP `172.22.132.9`。

> * 這邊`m`為 K8s Master 節點，`g`為 K8s Node 節點。
> * 所有操作全部用`root`使用者進行，主要方便部署用。

## 事前準備
開始部署叢集前需先確保以下條件已達成：
* `所有節點`彼此網路互通，並且`k8s-m1` SSH 登入其他節點為 passwdless，由於過程中很多會在某台節點(`k8s-m1`)上以 SSH 複製與操作其他節點。
* 確認所有防火牆與 SELinux 已關閉。如 CentOS：

```sh
$ systemctl stop firewalld && systemctl disable firewalld
$ setenforce 0
$ vim /etc/selinux/config
SELINUX=disabled
```
> 關閉是為了方便安裝使用，若有需要防火牆可以參考 [Required ports](https://kubernetes.io/docs/tasks/tools/install-kubeadm/#check-required-ports) 來設定。

* `所有節點`需要安裝 Docker CE 版本的容器引擎：

```sh
$ curl -fsSL https://get.docker.com/ | sh
```
> 不管是在 `Ubuntu` 或 `CentOS` 都只需要執行該指令就會自動安裝最新版 Docker。
> CentOS 安裝完成後，需要再執行以下指令：
```sh
$ systemctl enable docker && systemctl start docker
```

* 所有節點需要加入 APT 與 YUM Kubernetes package 來源：

```sh
$ curl -s "https://packages.cloud.google.com/apt/doc/apt-key.gpg" | apt-key add -
$ echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list
```
> 若是 CentOS 7 則執行以下方式：
```sh
$ cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=http://yum.kubernetes.io/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
       https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
```

* `所有節點`需要設定以下系統參數。

```sh
$ cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

$ sysctl -p /etc/sysctl.d/k8s.conf
```
> 關於`bridge-nf-call-iptables`的啟用取決於是否將容器連接到`Linux bridge`或使用其他一些機制(如 SDN vSwitch)。

* Kubernetes v1.8+ 要求關閉系統 Swap，請在`所有節點`利用以下指令關閉：

```sh
$ swapoff -a && sysctl -w vm.swappiness=0

# 不同機器會有差異
$ sed '/swap.img/d' -i /etc/fstab
```
> 記得`/etc/fstab`也要註解掉`SWAP`掛載。

## Kubernetes Master 建立
本節將說明如何部署與設定 Kubernetes Master 節點中的各元件。

在開始部署`master`節點元件前，請先安裝好 kubeadm、kubelet 等套件，並建立`/etc/kubernetes/manifests/`目錄存放 Static Pod 的 YAML 檔：
```sh
$ export KUBE_VERSION="1.11.0"
$ apt-get update && apt-get install -y kubelet=${KUBE_VERSION}-00 kubeadm=${KUBE_VERSION}-00 kubectl=${KUBE_VERSION}-00
$ mkdir -p /etc/kubernetes/manifests/
```

完成後，依照下面小節完成部署。

### HAProxy
本節將說明如何建立 HAProxy 來提供 Kubernetes API Server 的負載平衡。在所有`master`節點`/etc/haproxy/`目錄：
```sh
$ mkdir -p /etc/haproxy/
```

接著在所有`master`節點新增`/etc/haproxy/haproxy.cfg`設定檔，並加入以下內容：
```sh
$ cat <<EOF > /etc/haproxy/haproxy.cfg
global
  log 127.0.0.1 local0
  log 127.0.0.1 local1 notice
  tune.ssl.default-dh-param 2048

defaults
  log global
  mode http
  option dontlognull
  timeout connect 5000ms
  timeout client  600000ms
  timeout server  600000ms

listen stats
    bind :9090
    mode http
    balance
    stats uri /haproxy_stats
    stats auth admin:admin123
    stats admin if TRUE

frontend kube-apiserver-https
   mode tcp
   bind :8443
   default_backend kube-apiserver-backend

backend kube-apiserver-backend
    mode tcp
    balance roundrobin
    stick-table type ip size 200k expire 30m
    stick on src
    server apiserver1 172.22.132.10:6443 check
    server apiserver2 172.22.132.11:6443 check
    server apiserver3 172.22.132.12:6443 check
EOF
```
> 這邊會綁定`8443`作為 API Server 的 Proxy。

接著在新增一個路徑為`/etc/kubernetes/manifests/haproxy.yaml`的 YAML 檔來提供 HAProxy 的 Static Pod 部署，其內容如下：
```sh
$ cat <<EOF > /etc/kubernetes/manifests/haproxy.yaml
kind: Pod
apiVersion: v1
metadata:
  annotations:
    scheduler.alpha.kubernetes.io/critical-pod: ""
  labels:
    component: haproxy
    tier: control-plane
  name: kube-haproxy
  namespace: kube-system
spec:
  hostNetwork: true
  priorityClassName: system-cluster-critical
  containers:
  - name: kube-haproxy
    image: docker.io/haproxy:1.7-alpine
    resources:
      requests:
        cpu: 100m
    volumeMounts:
    - name: haproxy-cfg
      readOnly: true
      mountPath: /usr/local/etc/haproxy/haproxy.cfg
  volumes:
  - name: haproxy-cfg
    hostPath:
      path: /etc/haproxy/haproxy.cfg
      type: FileOrCreate
EOF
```

接下來將新增另一個 YAML 來提供部署 Keepalived。

### Keepalived
本節將說明如何建立 Keepalived 來提供 Kubernetes API Server 的 VIP。在所有`master`節點新增一個路徑為`/etc/kubernetes/manifests/keepalived.yaml`的 YAML 檔來提供 HAProxy 的 Static Pod 部署，其內容如下：
```sh
$ cat <<EOF > /etc/kubernetes/manifests/keepalived.yaml
kind: Pod
apiVersion: v1
metadata:
  annotations:
    scheduler.alpha.kubernetes.io/critical-pod: ""
  labels:
    component: keepalived
    tier: control-plane
  name: kube-keepalived
  namespace: kube-system
spec:
  hostNetwork: true
  priorityClassName: system-cluster-critical
  containers:
  - name: kube-keepalived
    image: docker.io/osixia/keepalived:1.4.5
    env:
    - name: KEEPALIVED_VIRTUAL_IPS
      value: 172.22.132.9
    - name: KEEPALIVED_INTERFACE
      value: enp3s0
    - name: KEEPALIVED_UNICAST_PEERS
      value: "#PYTHON2BASH:['172.22.132.10', '172.22.132.11', '172.22.132.12']"
    - name: KEEPALIVED_PASSWORD
      value: d0cker
    - name: KEEPALIVED_PRIORITY
      value: "100"
    - name: KEEPALIVED_ROUTER_ID
      value: "51"
    resources:
      requests:
        cpu: 100m
    securityContext:
      privileged: true
      capabilities:
        add:
        - NET_ADMIN
EOF
```
> * `KEEPALIVED_VIRTUAL_IPS`：Keepalived 提供的 VIPs。
> * `KEEPALIVED_INTERFACE`：VIPs 綁定的網卡。
> * `KEEPALIVED_UNICAST_PEERS`：其他 Keepalived 節點的單點傳播 IP。
> * `KEEPALIVED_PASSWORD`： Keepalived auth_type 的 Password。
> * `KEEPALIVED_PRIORITY`：指定了備援發生時，接手的介面之順序，數字越小，優先順序越高。這邊`k8s-m1`設為 100，其餘為`150`。
> * `KEEPALIVED_ROUTER_ID`：一組 Keepalived instance 的數字識別子。

### Kubernetes Control Plane
本節將說明如何透過 kubeadm 來建立 control plane 元件，這邊會分別對不同`master`節點建立初始化 config 檔，並執行不同初始化指令來建立。

#### Master1
首先在`k8s-m1`節點建立`kubeadm-config.yaml`的 Kubeadm Master Configuration 檔：
```sh
$ cat <<EOF > kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1alpha2
kind: MasterConfiguration
kubernetesVersion: v1.11.0
apiServerCertSANs:
- "172.22.132.9"
api:
  controlPlaneEndpoint: "172.22.132.9:8443"
etcd:
  local:
    extraArgs:
      listen-client-urls: "https://127.0.0.1:2379,https://172.22.132.10:2379"
      advertise-client-urls: "https://172.22.132.10:2379"
      listen-peer-urls: "https://172.22.132.10:2380"
      initial-advertise-peer-urls: "https://172.22.132.10:2380"
      initial-cluster: "k8s-m1=https://172.22.132.10:2380"
    serverCertSANs:
      - k8s-m1
      - 172.22.132.10
    peerCertSANs:
      - k8s-m1
      - 172.22.132.10
networking:
  podSubnet: "10.244.0.0/16"
EOF
```
> `apiServerCertSANs`欄位要填入 VIPs; `api.controlPlaneEndpoint`填入 VIPs 與 bind port。

新增完後，透過 kubeadm 來初始化 control plane：
```sh
$ kubeadm init --config kubeadm-config.yaml
```
> 這邊記得記下來 join 節點資訊，方便後面使用。雖然也可以用 token list 來取得。

經過一段時間完成後，接著透過 netstat 檢查是否正常啟動服務：
```sh
$ netstat -ntlp
Active Internet connections (only servers)
Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name
tcp        0      0 127.0.0.1:10249         0.0.0.0:*               LISTEN      9775/kube-proxy
tcp        0      0 127.0.0.1:10251         0.0.0.0:*               LISTEN      9410/kube-scheduler
tcp        0      0 172.22.132.10:2379      0.0.0.0:*               LISTEN      9339/etcd
tcp        0      0 127.0.0.1:2379          0.0.0.0:*               LISTEN      9339/etcd
tcp        0      0 172.22.132.10:2380      0.0.0.0:*               LISTEN      9339/etcd
tcp        0      0 127.0.0.1:10252         0.0.0.0:*               LISTEN      9271/kube-controlle
tcp        0      0 0.0.0.0:8443            0.0.0.0:*               LISTEN      9519/haproxy
tcp        0      0 0.0.0.0:9090            0.0.0.0:*               LISTEN      9519/haproxy
tcp        0      0 127.0.0.1:44614         0.0.0.0:*               LISTEN      8767/kubelet
tcp        0      0 127.0.0.1:10248         0.0.0.0:*               LISTEN      8767/kubelet
tcp6       0      0 :::10250                :::*                    LISTEN      8767/kubelet
tcp6       0      0 :::6443                 :::*                    LISTEN      9548/kube-apiserver
tcp6       0      0 :::10256                :::*                    LISTEN      9775/kube-proxy
```

經過一段時間完成後，執行以下指令來使用 kubeconfig：
```sh
$ mkdir -p $HOME/.kube
$ cp -rp /etc/kubernetes/admin.conf $HOME/.kube/config
$ chown $(id -u):$(id -g) $HOME/.kube/config
```

透過 kubectl 檢查 Kubernetes 叢集狀況：
```sh
$ kubectl get no
NAME      STATUS     ROLES     AGE       VERSION
k8s-m1    NotReady   master    5m        v1.11.0

$ kubectl -n kube-system get po
NAME                             READY     STATUS    RESTARTS   AGE
coredns-78fcdf6894-9pplt         0/1       Pending   0          5m
coredns-78fcdf6894-qwg58         0/1       Pending   0          5m
etcd-k8s-m1                      1/1       Running   0          4m
kube-apiserver-k8s-m1            1/1       Running   0          4m
kube-controller-manager-k8s-m1   1/1       Running   0          4m
kube-haproxy-k8s-m1              1/1       Running   0          4m
kube-keepalived-k8s-m1           1/1       Running   0          4m
kube-proxy-kngb6                 1/1       Running   0          5m
kube-scheduler-k8s-m1            1/1       Running   0          4m
```

上面完成後，在`k8s-m1`將 CA 與 Certs 複製到其他`master`節點上以供使用：
```sh
$ export DIR=/etc/kubernetes/
$ for NODE in k8s-m2 k8s-m3; do
    echo "------ ${NODE} ------"
    ssh ${NODE} "mkdir -p ${DIR}/pki/etcd"
    scp ${DIR}/pki/ca.crt ${NODE}:${DIR}/pki/ca.crt
    scp ${DIR}/pki/ca.key ${NODE}:${DIR}/pki/ca.key
    scp ${DIR}/pki/sa.key ${NODE}:${DIR}/pki/sa.key
    scp ${DIR}/pki/sa.pub ${NODE}:${DIR}/pki/sa.pub
    scp ${DIR}/pki/front-proxy-ca.crt ${NODE}:${DIR}/pki/front-proxy-ca.crt
    scp ${DIR}/pki/front-proxy-ca.key ${NODE}:${DIR}/pki/front-proxy-ca.key
    scp ${DIR}/pki/etcd/ca.crt ${NODE}:${DIR}/pki/etcd/ca.crt
    scp ${DIR}/pki/etcd/ca.key ${NODE}:${DIR}/pki/etcd/ca.key
    scp ${DIR}/admin.conf ${NODE}:${DIR}/admin.conf
  done
```

#### Master2
首先在`k8s-m2`節點建立`kubeadm-config.yaml`的 Kubeadm Master Configuration 檔：
```sh
$ cat <<EOF > kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1alpha2
kind: MasterConfiguration
kubernetesVersion: v1.11.0
apiServerCertSANs:
- "172.22.132.9"
api:
  controlPlaneEndpoint: "172.22.132.9:8443"
etcd:
  local:
    extraArgs:
      listen-client-urls: "https://127.0.0.1:2379,https://172.22.132.11:2379"
      advertise-client-urls: "https://172.22.132.11:2379"
      listen-peer-urls: "https://172.22.132.11:2380"
      initial-advertise-peer-urls: "https://172.22.132.11:2380"
      initial-cluster: "k8s-m1=https://172.22.132.10:2380,k8s-m2=https://172.22.132.11:2380"
      initial-cluster-state: existing
    serverCertSANs:
      - k8s-m2
      - 172.22.132.11
    peerCertSANs:
      - k8s-m2
      - 172.22.132.11
networking:
  podSubnet: "10.244.0.0/16"
EOF
```

新增完後，透過 kubeadm phase 來啟動`k8s-m2`的 kubelet：
```sh
$ kubeadm alpha phase certs all --config kubeadm-config.yaml
$ kubeadm alpha phase kubelet config write-to-disk --config kubeadm-config.yaml
$ kubeadm alpha phase kubelet write-env-file --config kubeadm-config.yaml
$ kubeadm alpha phase kubeconfig kubelet --config kubeadm-config.yaml
$ systemctl start kubelet
```

接著執行以下指令來加入節點至 etcd cluster：
```sh
$ export ETCD1_NAME=k8s-m1; export ETCD1_IP=172.22.132.10
$ export ETCD2_NAME=k8s-m2; export ETCD2_IP=172.22.132.11
$ export KUBECONFIG=/etc/kubernetes/admin.conf
$ kubectl exec -n kube-system etcd-${ETCD1_NAME} -- etcdctl \
    --ca-file /etc/kubernetes/pki/etcd/ca.crt \
    --cert-file /etc/kubernetes/pki/etcd/peer.crt \
    --key-file /etc/kubernetes/pki/etcd/peer.key \
    --endpoints=https://${ETCD1_IP}:2379 member add ${ETCD2_NAME} https://${ETCD2_IP}:2380

$ kubeadm alpha phase etcd local --config kubeadm-config.yaml
```

最後執行以下指令來部署 control plane：
```sh
$ kubeadm alpha phase kubeconfig all --config kubeadm-config.yaml
$ kubeadm alpha phase controlplane all --config kubeadm-config.yaml
$ kubeadm alpha phase mark-master --config kubeadm-config.yaml
```

經過一段時間完成後，執行以下指令來使用 kubeconfig：
```sh
$ mkdir -p $HOME/.kube
$ cp -rp /etc/kubernetes/admin.conf $HOME/.kube/config
$ chown $(id -u):$(id -g) $HOME/.kube/config
```

透過 kubectl 檢查 Kubernetes 叢集狀況：
```sh
$ kubectl get no
NAME      STATUS     ROLES     AGE       VERSION
k8s-m1    NotReady   master    10m       v1.11.0
k8s-m2    NotReady   master    1m        v1.11.0
```

#### Master3
首先在`k8s-m3`節點建立`kubeadm-config.yaml`的 Kubeadm Master Configuration 檔：
```sh
$ cat <<EOF > kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1alpha2
kind: MasterConfiguration
kubernetesVersion: v1.11.0
apiServerCertSANs:
- "172.22.132.9"
api:
  controlPlaneEndpoint: "172.22.132.9:8443"
etcd:
  local:
    extraArgs:
      listen-client-urls: "https://127.0.0.1:2379,https://172.22.132.12:2379"
      advertise-client-urls: "https://172.22.132.12:2379"
      listen-peer-urls: "https://172.22.132.12:2380"
      initial-advertise-peer-urls: "https://172.22.132.12:2380"
      initial-cluster: "k8s-m1=https://172.22.132.10:2380,k8s-m2=https://172.22.132.11:2380,k8s-m3=https://172.22.132.12:2380"
      initial-cluster-state: existing
    serverCertSANs:
      - k8s-m3
      - 172.22.132.12
    peerCertSANs:
      - k8s-m3
      - 172.22.132.12
networking:
  podSubnet: "10.244.0.0/16"
EOF
```

新增完後，透過 kubeadm phase 來啟動`k8s-m3`的 kubelet：
```sh
$ kubeadm alpha phase certs all --config kubeadm-config.yaml
$ kubeadm alpha phase kubelet config write-to-disk --config kubeadm-config.yaml
$ kubeadm alpha phase kubelet write-env-file --config kubeadm-config.yaml
$ kubeadm alpha phase kubeconfig kubelet --config kubeadm-config.yaml
$ systemctl start kubelet
```

接著執行以下指令來加入節點至 etcd cluster：
```sh
$ export ETCD1_NAME=k8s-m1; export ETCD1_IP=172.22.132.10
$ export ETCD3_NAME=k8s-m3; export ETCD3_IP=172.22.132.12
$ export KUBECONFIG=/etc/kubernetes/admin.conf
$ kubectl exec -n kube-system etcd-${ETCD1_NAME} -- etcdctl \
    --ca-file /etc/kubernetes/pki/etcd/ca.crt \
    --cert-file /etc/kubernetes/pki/etcd/peer.crt \
    --key-file /etc/kubernetes/pki/etcd/peer.key \
    --endpoints=https://${ETCD1_IP}:2379 member add ${ETCD3_NAME} https://${ETCD3_IP}:2380

$ kubeadm alpha phase etcd local --config kubeadm-config.yaml
```
> 此過程與`k8s-m2`相同，只是修改要加入的 member 名稱與 IP。

最後執行以下指令來部署 control plane：
```sh
$ kubeadm alpha phase kubeconfig all --config kubeadm-config.yaml
$ kubeadm alpha phase controlplane all --config kubeadm-config.yaml
$ kubeadm alpha phase mark-master --config kubeadm-config.yaml
```
> 此過程與`k8s-m2`相同。

經過一段時間完成後，執行以下指令來使用 kubeconfig：
```sh
$ mkdir -p $HOME/.kube
$ cp -rp /etc/kubernetes/admin.conf $HOME/.kube/config
$ chown $(id -u):$(id -g) $HOME/.kube/config
```
> 此過程與`k8s-m2`相同。

透過 kubectl 檢查 Kubernetes 叢集狀況：
```sh
$ kubectl get no
NAME      STATUS     ROLES     AGE       VERSION
k8s-m1    NotReady   master    20m       v1.11.0
k8s-m2    NotReady   master    10m       v1.11.0
k8s-m3    NotReady   master    1m        v1.11.0
```
> 此過程與`k8s-m2`相同。

若有更多`master`節點則以此類推部署，建議透過 CM tools(ex: ansible、puppet) 來撰寫腳本完成。

### 建立 Pod Network
當`master`節點都完成部署後，接著要在此 Kubernetes 部署 Pod Network Plugin，這邊採用 CoreOS Flannel 來提供簡單 Overlay Network 來讓 Pod 中的容器能夠互相溝通：
```sh
$ kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/v0.10.0/Documentation/kube-flannel.yml
clusterrole "flannel" created
clusterrolebinding "flannel" created
serviceaccount "flannel" configured
configmap "kube-flannel-cfg" configured
daemonset "kube-flannel-ds" configured
```
> * 若參數 `--pod-network-cidr=10.244.0.0/16` 改變時，在`kube-flannel.yml`檔案也需修改`net-conf.json`欄位的 CIDR。
> * 若使用 Virtualbox 的話，請修改`kube-flannel.yml`中的 command 綁定 iface，如`command: [ "/opt/bin/flanneld", "--ip-masq", "--kube-subnet-mgr", "--iface=eth1" ]`。
> * 其他 Pod Network 可以參考 [Installing a pod network](https://kubernetes.io/docs/setup/independent/create-cluster-kubeadm/#pod-network)。

接著透過 kubectl 查看 Flannel 是否正確在每個 Node 部署：
確認 Flannel 部署正確：
```sh
$ kubectl -n kube-system get po -l app=flannel -o wide
NAME                    READY     STATUS    RESTARTS   AGE       IP              NODE
kube-flannel-ds-2ssnj   1/1       Running   0          58s       172.22.132.10   k8s-m1
kube-flannel-ds-pgfpd   1/1       Running   0          58s       172.22.132.11   k8s-m2
kube-flannel-ds-vmt2h   1/1       Running   0          58s       172.22.132.12   k8s-m3

$ ip -4 a show flannel.1
5: flannel.1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc noqueue state UNKNOWN group default
    inet 10.244.0.0/32 scope global flannel.1
       valid_lft forever preferred_lft forever

$ route -n
Kernel IP routing table
Destination     Gateway         Genmask         Flags Metric Ref    Use Iface
...
10.244.0.0      0.0.0.0         255.255.255.0   U     0      0        0 cni0
10.244.1.0      10.244.1.0      255.255.255.0   UG    0      0        0 flannel.1
10.244.2.0      10.244.2.0      255.255.255.0   UG    0      0        0 flannel.1
```

## Kubernetes Node 建立
本節將說明如何部署與設定 Kubernetes Node 節點中。

在開始部署`node`節點元件前，請先安裝好 kubeadm、kubelet 等套件，並建立`/etc/kubernetes/manifests/`目錄存放 Static Pod 的 YAML 檔：
```sh
$ export KUBE_VERSION="1.11.0"
$ apt-get update && apt-get install -y kubelet=${KUBE_VERSION}-00 kubeadm=${KUBE_VERSION}-00
$ mkdir -p /etc/kubernetes/manifests/
```

安裝好後，接著在所有`node`節點透過 kubeadm 來加入節點：
```sh
$ kubeadm join 172.22.132.9:8443 \
    --token t4zvev.8pasuf89x2ze8htv \
    --discovery-token-ca-cert-hash sha256:19c373b19e71b03d89cfc6bdbd59e8f11bd691399b38e7eea11b6043ba73f91d
```

## 部署結果測試
當節點都完成後，進入`master`節點透過 kubectl 來檢查：
```sh
$ kubectl get no
NAME      STATUS    ROLES     AGE       VERSION
k8s-g1    Ready     <none>    1m        v1.11.0
k8s-g2    Ready     <none>    1m        v1.11.0
k8s-m1    Ready     master    30m       v1.11.0
k8s-m2    Ready     master    20m       v1.11.0
k8s-m3    Ready     master    11m       v1.11.0

$  kubectl get cs
NAME                 STATUS    MESSAGE              ERROR
scheduler            Healthy   ok
controller-manager   Healthy   ok
etcd-0               Healthy   {"health": "true"}
```
> kubeadm 的方式會讓狀態只顯示 etcd-0。


接著進入`k8s-m1`節點測試叢集 HA 功能，這邊先關閉該節點：
```sh
$ sudo poweroff
```

接著進入到`k8s-m2`節點，透過 kubectl 來檢查叢集是否能夠正常執行：
```sh
# 先檢查元件狀態
$ kubectl get cs
NAME                 STATUS    MESSAGE              ERROR
scheduler            Healthy   ok
controller-manager   Healthy   ok
etcd-0               Healthy   {"health": "true"}

# 檢查 nodes 狀態
$ kubectl get no
NAME      STATUS     ROLES     AGE       VERSION
k8s-g1    Ready      <none>    7m        v1.11.0
k8s-g2    Ready      <none>    7m        v1.11.0
k8s-m1    NotReady   master    37m       v1.11.0
k8s-m2    Ready      master    27m       v1.11.0
k8s-m3    Ready      master    18m       v1.11.0

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
$ curl 172.22.132.11:31780
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
...
```
