---
title: Kubernetes v1.11.x HA 全手動苦工安裝教學(TL;DR)
subtitle: ""
date: 2018-07-09 17:08:54
catalog: true
header-img: /images/kube/bg.png
categories:
- Kubernetes
tags:
- Kubernetes
- Docker
- Calico
---
本篇延續過往`手動安裝方式`來部署 Kubernetes v1.11.x 版本的 High Availability 叢集，而此次教學將直接透過裸機進行部署 Kubernetes 叢集。以手動安裝的目標是學習 Kubernetes 各元件關析、流程、設定與部署方式。若不想這麼累的話，可以參考 [Picking the Right Solution](https://kubernetes.io/docs/getting-started-guides/) 來選擇自己最喜歡的方式。

![](/images/kube/kubernetes-aa-ha.png)

<!--more-->

## Kubernetes 部署資訊
Kubernetes 部署的版本資訊：

* Kubernetes: v1.11.0
* CNI: v0.7.1
* Etcd: v3.3.8
* Docker: v18.05.0-ce
* Calico: v3.1

Kubernetes 部署的網路資訊：

* **Cluster IP CIDR**: 10.244.0.0/16
* **Service Cluster IP CIDR**: 10.96.0.0/12
* **Service DNS IP**: 10.96.0.10
* **DNS DN**: cluster.local
* **Kubernetes API VIP**: 172.22.132.9
* **Kubernetes Ingress VIP**: 172.22.132.8

## 節點資訊
本教學採用以下節點數與機器規格進行部署裸機(Bare-metal)，作業系統採用`Ubuntu 16+`(理論上 CentOS 7+ 也行)進行測試：

| IP Address  | Hostname | CPU | Memory | Extra Device |
|-------------|----------|-----|--------|--------------|
|172.22.132.10| k8s-m1   | 4   | 16G    | None         |
|172.22.132.11| k8s-m2   | 4   | 16G    | None         |
|172.22.132.12| k8s-m3   | 4   | 16G    | None         |
|172.22.132.13| k8s-g1   | 4   | 16G    | GTX 1060 3G  |
|172.22.132.14| k8s-g2   | 4   | 16G    | GTX 1060 3G  |

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

* `所有節點`需要設定`/etc/hosts`解析到所有叢集主機。

```
...
172.22.132.10 k8s-m1
172.22.132.11 k8s-m2
172.22.132.12 k8s-m3
172.22.132.13 k8s-g1
172.22.132.14 k8s-g2
```

* `所有節點`需要安裝 Docker CE 版本的容器引擎：

```sh
$ curl -fsSL https://get.docker.com/ | sh
```
> 不管是在 `Ubuntu` 或 `CentOS` 都只需要執行該指令就會自動安裝最新版 Docker。
> CentOS 安裝完成後，需要再執行以下指令：
```sh
$ systemctl enable docker && systemctl start docker
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

* 在`所有節點`下載 Kubernetes 二進制執行檔：

```sh
$ export KUBE_URL=https://storage.googleapis.com/kubernetes-release/release/v1.11.0/bin/linux/amd64
$ wget ${KUBE_URL}/kubelet -O /usr/local/bin/kubelet
$ chmod +x /usr/local/bin/kubelet

# Node 可忽略下載 kubectl
$ wget ${KUBE_URL}/kubectl -O /usr/local/bin/kubectl
$ chmod +x /usr/local/bin/kubectl
```

* 在`所有節點`下載 Kubernetes CNI 二進制執行檔：

```sh
$ export CNI_URL=https://github.com/containernetworking/plugins/releases/download
$ mkdir -p /opt/cni/bin && cd /opt/cni/bin
$ wget -qO- --show-progress "${CNI_URL}/v0.7.1/cni-plugins-amd64-v0.7.1.tgz" | tar -zx
```

* 在`k8s-m1`節點安裝`cfssl`工具，這將會用來建立 CA ，並產生 TLS 憑證。

```sh
$ export CFSSL_URL=https://pkg.cfssl.org/R1.2
$ wget ${CFSSL_URL}/cfssl_linux-amd64 -O /usr/local/bin/cfssl
$ wget ${CFSSL_URL}/cfssljson_linux-amd64 -O /usr/local/bin/cfssljson
$ chmod +x /usr/local/bin/cfssl /usr/local/bin/cfssljson
```

## 建立 CA 與產生 TLS 憑證
本節將會透過 CFSSL 工具來產生不同元件的憑證，如 Etcd、Kubernetes API Server 等等，其中各元件都會有一個根數位憑證認證機構(Root Certificate Authority)被用在元件之間的認證。

> 要注意 CA JSON 檔中的`CN(Common Name)`與`O(Organization)`等內容是會影響 Kubernetes 元件認證的。

首先在`k8s-m1`透過 Git 取得部署用檔案：
```sh
$ git clone https://github.com/kairen/k8s-manual-files.git ~/k8s-manual-files
$ cd ~/k8s-manual-files/pki
```

### Etcd
在`k8s-m1`建立`/etc/etcd/ssl`資料夾，並產生 Etcd CA：
```sh
$ export DIR=/etc/etcd/ssl
$ mkdir -p ${DIR}
$ cfssl gencert -initca etcd-ca-csr.json | cfssljson -bare ${DIR}/etcd-ca
```

接著產生 Etcd 憑證：
```sh
$ cfssl gencert \
  -ca=${DIR}/etcd-ca.pem \
  -ca-key=${DIR}/etcd-ca-key.pem \
  -config=ca-config.json \
  -hostname=127.0.0.1,172.22.132.10,172.22.132.11,172.22.132.12 \
  -profile=kubernetes \
  etcd-csr.json | cfssljson -bare ${DIR}/etcd
```
> `-hostname`需修改成所有 masters 節點。

刪除不必要的檔案，並檢查`/etc/etcd/ssl`目錄是否成功建立以下檔案：
```sh
$ rm -rf ${DIR}/*.csr
$ ls /etc/etcd/ssl
etcd-ca-key.pem  etcd-ca.pem  etcd-key.pem  etcd.pem
```

複製檔案至其他 Etcd 節點，這邊為所有`master`節點：
```sh
$ for NODE in k8s-m2 k8s-m3; do
    echo "--- $NODE ---"
    ssh ${NODE} " mkdir -p /etc/etcd/ssl"
    for FILE in etcd-ca-key.pem  etcd-ca.pem  etcd-key.pem  etcd.pem; do
      scp /etc/etcd/ssl/${FILE} ${NODE}:/etc/etcd/ssl/${FILE}
    done
  done
```

### Kubernetes 元件
在`k8s-m1`建立`/etc/kubernetes/pki`資料夾，並依據下面指令來產生 CA：
```sh
$ export K8S_DIR=/etc/kubernetes
$ export PKI_DIR=${K8S_DIR}/pki
$ export KUBE_APISERVER=https://172.22.132.9:6443
$ mkdir -p ${PKI_DIR}
$ cfssl gencert -initca ca-csr.json | cfssljson -bare ${PKI_DIR}/ca
$ ls ${PKI_DIR}/ca*.pem
/etc/kubernetes/pki/ca-key.pem  /etc/kubernetes/pki/ca.pem
```
> `KUBE_APISERVER`這邊設定為 VIP 位址。

接著依照以下小節來建立各元件的 TLS 憑證。

#### API Server
此憑證將被用於 API Server 與 Kubelet Client 溝通使用。首先透過以下指令產生 Kubernetes API Server 憑證：
```sh
$ cfssl gencert \
  -ca=${PKI_DIR}/ca.pem \
  -ca-key=${PKI_DIR}/ca-key.pem \
  -config=ca-config.json \
  -hostname=10.96.0.1,172.22.132.9,127.0.0.1,kubernetes.default \
  -profile=kubernetes \
  apiserver-csr.json | cfssljson -bare ${PKI_DIR}/apiserver

$ ls ${PKI_DIR}/apiserver*.pem
/etc/kubernetes/pki/apiserver-key.pem  /etc/kubernetes/pki/apiserver.pem
```
> 這邊`-hostname`的`10.96.0.1`是 Cluster IP 的 Kubernetes 端點; `172.22.132.9`為 VIP 位址; `kubernetes.default`為 Kubernetes 系統在 default namespace 自動建立的 API service domain name。

#### Front Proxy Client
此憑證將被用於 Authenticating Proxy 的功能上，而該功能主要是提供 API Aggregation 的認證。首先透過以下指令產生 CA：
```sh
$ cfssl gencert -initca front-proxy-ca-csr.json | cfssljson -bare ${PKI_DIR}/front-proxy-ca
$ ls ${PKI_DIR}/front-proxy-ca*.pem
/etc/kubernetes/pki/front-proxy-ca-key.pem  /etc/kubernetes/pki/front-proxy-ca.pem
```

接著產生 Front proxy client 憑證：
```sh
$ cfssl gencert \
  -ca=${PKI_DIR}/front-proxy-ca.pem \
  -ca-key=${PKI_DIR}/front-proxy-ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  front-proxy-client-csr.json | cfssljson -bare ${PKI_DIR}/front-proxy-client

$ ls ${PKI_DIR}/front-proxy-client*.pem
/etc/kubernetes/pki/front-proxy-client-key.pem  /etc/kubernetes/pki/front-proxy-client.pem
```

#### Controller Manager
憑證會建立`system:kube-controller-manager`的使用者(憑證 CN)，並被綁定在 RBAC Cluster Role 中的`system:kube-controller-manager`來讓 Controller Manager 元件能夠存取需要的 API object。這邊透過以下指令產生 Controller Manager 憑證：
```sh
$ cfssl gencert \
  -ca=${PKI_DIR}/ca.pem \
  -ca-key=${PKI_DIR}/ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  manager-csr.json | cfssljson -bare ${PKI_DIR}/controller-manager

$ ls ${PKI_DIR}/controller-manager*.pem
/etc/kubernetes/pki/controller-manager-key.pem  /etc/kubernetes/pki/controller-manager.pem
```

接著利用 kubectl 來產生 Controller Manager 的 kubeconfig 檔：
```sh
$ kubectl config set-cluster kubernetes \
    --certificate-authority=${PKI_DIR}/ca.pem \
    --embed-certs=true \
    --server=${KUBE_APISERVER} \
    --kubeconfig=${K8S_DIR}/controller-manager.conf

$ kubectl config set-credentials system:kube-controller-manager \
    --client-certificate=${PKI_DIR}/controller-manager.pem \
    --client-key=${PKI_DIR}/controller-manager-key.pem \
    --embed-certs=true \
    --kubeconfig=${K8S_DIR}/controller-manager.conf

$ kubectl config set-context system:kube-controller-manager@kubernetes \
    --cluster=kubernetes \
    --user=system:kube-controller-manager \
    --kubeconfig=${K8S_DIR}/controller-manager.conf

$ kubectl config use-context system:kube-controller-manager@kubernetes \
    --kubeconfig=${K8S_DIR}/controller-manager.conf
```

#### Scheduler
憑證會建立`system:kube-scheduler`的使用者(憑證 CN)，並被綁定在 RBAC Cluster Role 中的`system:kube-scheduler`來讓 Scheduler 元件能夠存取需要的 API object。這邊透過以下指令產生 Scheduler 憑證：
```sh
$ cfssl gencert \
  -ca=${PKI_DIR}/ca.pem \
  -ca-key=${PKI_DIR}/ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  scheduler-csr.json | cfssljson -bare ${PKI_DIR}/scheduler

$ ls ${PKI_DIR}/scheduler*.pem
/etc/kubernetes/pki/scheduler-key.pem  /etc/kubernetes/pki/scheduler.pem
```

接著利用 kubectl 來產生 Scheduler 的 kubeconfig 檔：
```sh
$ kubectl config set-cluster kubernetes \
    --certificate-authority=${PKI_DIR}/ca.pem \
    --embed-certs=true \
    --server=${KUBE_APISERVER} \
    --kubeconfig=${K8S_DIR}/scheduler.conf

$ kubectl config set-credentials system:kube-scheduler \
    --client-certificate=${PKI_DIR}/scheduler.pem \
    --client-key=${PKI_DIR}/scheduler-key.pem \
    --embed-certs=true \
    --kubeconfig=${K8S_DIR}/scheduler.conf

$ kubectl config set-context system:kube-scheduler@kubernetes \
    --cluster=kubernetes \
    --user=system:kube-scheduler \
    --kubeconfig=${K8S_DIR}/scheduler.conf

$ kubectl config use-context system:kube-scheduler@kubernetes \
    --kubeconfig=${K8S_DIR}/scheduler.conf
```

#### Admin
Admin 被用來綁定 RBAC Cluster Role 中 cluster-admin，當想要操作所有 Kubernetes 叢集功能時，就必須利用這邊產生的 kubeconfig 檔案。這邊透過以下指令產生 Kubernetes Admin 憑證：
```sh
$ cfssl gencert \
  -ca=${PKI_DIR}/ca.pem \
  -ca-key=${PKI_DIR}/ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  admin-csr.json | cfssljson -bare ${PKI_DIR}/admin

$ ls ${PKI_DIR}/admin*.pem
/etc/kubernetes/pki/admin-key.pem  /etc/kubernetes/pki/admin.pem
```

接著利用 kubectl 來產生 Admin 的 kubeconfig 檔：
```sh
$ kubectl config set-cluster kubernetes \
    --certificate-authority=${PKI_DIR}/ca.pem \
    --embed-certs=true \
    --server=${KUBE_APISERVER} \
    --kubeconfig=${K8S_DIR}/admin.conf

$ kubectl config set-credentials kubernetes-admin \
    --client-certificate=${PKI_DIR}/admin.pem \
    --client-key=${PKI_DIR}/admin-key.pem \
    --embed-certs=true \
    --kubeconfig=${K8S_DIR}/admin.conf

$ kubectl config set-context kubernetes-admin@kubernetes \
    --cluster=kubernetes \
    --user=kubernetes-admin \
    --kubeconfig=${K8S_DIR}/admin.conf

$ kubectl config use-context kubernetes-admin@kubernetes \
    --kubeconfig=${K8S_DIR}/admin.conf
```

#### Masters Kubelet
這邊使用 [Node authorizer](https://kubernetes.io/docs/reference/access-authn-authz/node/) 來讓節點的 kubelet 能夠存取如 services、endpoints 等 API，而使用 Node authorizer 需定義 `system:nodes` 群組(憑證的 Organization)，並且包含`system:node:<nodeName>`的使用者名稱(憑證的 Common Name)。

首先在`k8s-m1`節點產生所有 master 節點的 kubelet 憑證，這邊透過下面腳本來產生：
```sh
$ for NODE in k8s-m1 k8s-m2 k8s-m3; do
    echo "--- $NODE ---"
    cp kubelet-csr.json kubelet-$NODE-csr.json;
    sed -i "s/\$NODE/$NODE/g" kubelet-$NODE-csr.json;
    cfssl gencert \
      -ca=${PKI_DIR}/ca.pem \
      -ca-key=${PKI_DIR}/ca-key.pem \
      -config=ca-config.json \
      -hostname=$NODE \
      -profile=kubernetes \
      kubelet-$NODE-csr.json | cfssljson -bare ${PKI_DIR}/kubelet-$NODE;
    rm kubelet-$NODE-csr.json
  done

$ ls ${PKI_DIR}/kubelet*.pem
/etc/kubernetes/pki/kubelet-k8s-m1-key.pem  /etc/kubernetes/pki/kubelet-k8s-m2.pem
/etc/kubernetes/pki/kubelet-k8s-m1.pem      /etc/kubernetes/pki/kubelet-k8s-m3-key.pem
/etc/kubernetes/pki/kubelet-k8s-m2-key.pem  /etc/kubernetes/pki/kubelet-k8s-m3.pem
```

產生完成後，將 kubelet 憑證複製到所有`master`節點上：
```sh
$ for NODE in k8s-m1 k8s-m2 k8s-m3; do
    echo "--- $NODE ---"
    ssh ${NODE} "mkdir -p ${PKI_DIR}"
    scp ${PKI_DIR}/ca.pem ${NODE}:${PKI_DIR}/ca.pem
    scp ${PKI_DIR}/kubelet-$NODE-key.pem ${NODE}:${PKI_DIR}/kubelet-key.pem
    scp ${PKI_DIR}/kubelet-$NODE.pem ${NODE}:${PKI_DIR}/kubelet.pem
    rm ${PKI_DIR}/kubelet-$NODE-key.pem ${PKI_DIR}/kubelet-$NODE.pem
  done
```

接著利用 kubectl 來產生 kubelet 的 kubeconfig 檔，這邊透過腳本來產生所有`master`節點的檔案：
```sh
$ for NODE in k8s-m1 k8s-m2 k8s-m3; do
    echo "--- $NODE ---"
    ssh ${NODE} "cd ${PKI_DIR} && \
      kubectl config set-cluster kubernetes \
        --certificate-authority=${PKI_DIR}/ca.pem \
        --embed-certs=true \
        --server=${KUBE_APISERVER} \
        --kubeconfig=${K8S_DIR}/kubelet.conf && \
      kubectl config set-credentials system:node:${NODE} \
        --client-certificate=${PKI_DIR}/kubelet.pem \
        --client-key=${PKI_DIR}/kubelet-key.pem \
        --embed-certs=true \
        --kubeconfig=${K8S_DIR}/kubelet.conf && \
      kubectl config set-context system:node:${NODE}@kubernetes \
        --cluster=kubernetes \
        --user=system:node:${NODE} \
        --kubeconfig=${K8S_DIR}/kubelet.conf && \
      kubectl config use-context system:node:${NODE}@kubernetes \
        --kubeconfig=${K8S_DIR}/kubelet.conf"
  done
```

#### Service Account Key
Kubernetes Controller Manager 利用 Key pair 來產生與簽署 Service Account 的 tokens，而這邊不透過 CA 做認證，而是建立一組公私鑰來讓 API Server 與 Controller Manager 使用：
```sh
$ openssl genrsa -out ${PKI_DIR}/sa.key 2048
$ openssl rsa -in ${PKI_DIR}/sa.key -pubout -out ${PKI_DIR}/sa.pub
$ ls ${PKI_DIR}/sa.*
/etc/kubernetes/pki/sa.key  /etc/kubernetes/pki/sa.pub
```

#### 刪除不必要檔案
當所有檔案建立與產生完成後，將一些不必要檔案刪除：
```sh
$ rm -rf ${PKI_DIR}/*.csr \
    ${PKI_DIR}/scheduler*.pem \
    ${PKI_DIR}/controller-manager*.pem \
    ${PKI_DIR}/admin*.pem \
    ${PKI_DIR}/kubelet*.pem
```

#### 複製檔案至其他節點
將憑證複製到其他`master`節點：
```sh
$ for NODE in k8s-m2 k8s-m3; do
    echo "--- $NODE ---"
    for FILE in $(ls ${PKI_DIR}); do
      scp ${PKI_DIR}/${FILE} ${NODE}:${PKI_DIR}/${FILE}
    done
  done
```

複製各元件 kubeconfig 檔案至其他`master`節點：
```sh
$ for NODE in k8s-m2 k8s-m3; do
    echo "--- $NODE ---"
    for FILE in admin.conf controller-manager.conf scheduler.conf; do
      scp ${K8S_DIR}/${FILE} ${NODE}:${K8S_DIR}/${FILE}
    done
  done
```

## Kubernetes Masters
本節將說明如何部署與設定 Kubernetes Master 角色中的各元件，在開始前先簡單了解一下各元件功能：

* **kubelet**：負責管理容器的生命週期，定期從 API Server 取得節點上的預期狀態(如網路、儲存等等配置)資源，並呼叫對應的容器介面(CRI、CNI 等)來達成這個狀態。任何 Kubernetes 節點都會擁有該元件。
* **kube-apiserver**：以 REST APIs 提供 Kubernetes 資源的 CRUD，如授權、認證、存取控制與 API 註冊等機制。
* **kube-controller-manager**：透過核心控制循環(Core Control Loop)監聽 Kubernetes API 的資源來維護叢集的狀態，這些資源會被不同的控制器所管理，如 Replication Controller、Namespace Controller 等等。而這些控制器會處理著自動擴展、滾動更新等等功能。
* **kube-scheduler**：負責將一個(或多個)容器依據排程策略分配到對應節點上讓容器引擎(如 Docker)執行。而排程受到 QoS 要求、軟硬體約束、親和性(Affinity)等等規範影響。
* **Etcd**：用來保存叢集所有狀態的 Key/Value 儲存系統，所有 Kubernetes 元件會透過 API Server 來跟 Etcd 進行溝通來保存或取得資源狀態。
* **HAProxy**：提供多個 API Server 的負載平衡(Load Balance)。
* **Keepalived**：建立一個虛擬 IP(VIP) 來作為 API Server 統一存取端點。

而上述元件除了 kubelet 外，其他將透過 kubelet 以 [Static Pod](https://kubernetes.io/docs/tasks/administer-cluster/static-pod/) 方式進行部署，這種方式可以減少管理 Systemd 的服務，並且能透過 kubectl 來觀察啟動的容器狀況。

### 部署與設定
首先在`k8s-m1`節點進入`k8s-manual-files`目錄，並依序執行下述指令來完成部署：
```sh
$ cd ~/k8s-manual-files
```

首先利用`./hack/gen-configs.sh`腳本在每台`master`節點產生組態檔：
```sh
$ export NODES="k8s-m1 k8s-m2 k8s-m3"
$ ./hack/gen-configs.sh
k8s-m1 config generated...
k8s-m2 config generated...
k8s-m3 config generated...
```

完成後記得檢查`/etc/etcd/config.yml`與`/etc/haproxy/haproxy.cfg`是否設定正確。
> 這邊主要確認檔案中的`${xxx}`字串是否有被更改，並且符合環境。詳細內容可以查看`k8s-manual-files`。

接著利用`./hack/gen-manifests.sh`腳本在每台`master`節點產生 Static pod YAML 檔案，以及其他相關設定檔(如 EncryptionConfig)：
```sh
$ export NODES="k8s-m1 k8s-m2 k8s-m3"
$ ./hack/gen-manifests.sh
k8s-m1 manifests generated...
k8s-m2 manifests generated...
k8s-m3 manifests generated...
```

完成後記得檢查`/etc/kubernetes/manifests`、`/etc/kubernetes/encryption`與`/etc/kubernetes/audit`目錄中的檔案是否是定正確。
> 這邊主要確認檔案中的`${xxx}`字串是否有被更改，並且符合環境需求。詳細內容可以查看`k8s-manual-files`。

確認上述兩個產生檔案步驟完成後，即可設定所有`master`節點的 kubelet systemd 來啟動 Kubernetes 元件。首先複製下列檔案到指定路徑：
```sh
$ for NODE in k8s-m1 k8s-m2 k8s-m3; do
    echo "--- $NODE ---"
    ssh ${NODE} "mkdir -p /var/lib/kubelet /var/log/kubernetes /var/lib/etcd /etc/systemd/system/kubelet.service.d"
    scp master/var/lib/kubelet/config.yml ${NODE}:/var/lib/kubelet/config.yml
    scp master/systemd/kubelet.service ${NODE}:/lib/systemd/system/kubelet.service
    scp master/systemd/10-kubelet.conf ${NODE}:/etc/systemd/system/kubelet.service.d/10-kubelet.conf
  done
```

接著在`k8s-m1`透過 SSH 啟動所有`master`節點的 kubelet：
```sh
$ for NODE in k8s-m1 k8s-m2 k8s-m3; do
    ssh ${NODE} "systemctl enable kubelet.service && systemctl start kubelet.service"
  done
```

完成後會需要一段時間來下載映像檔與啟動元件，可以利用該指令來監看：
```sh
$ watch netstat -ntlp
Active Internet connections (only servers)
Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name
tcp        0      0 127.0.0.1:10251         0.0.0.0:*               LISTEN      9407/kube-scheduler
tcp        0      0 127.0.0.1:10252         0.0.0.0:*               LISTEN      9338/kube-controlle
tcp        0      0 127.0.0.1:38420         0.0.0.0:*               LISTEN      8676/kubelet
tcp        0      0 0.0.0.0:8443            0.0.0.0:*               LISTEN      9602/haproxy
tcp        0      0 0.0.0.0:9090            0.0.0.0:*               LISTEN      9602/haproxy
tcp6       0      0 :::10250                :::*                    LISTEN      8676/kubelet
tcp6       0      0 :::2379                 :::*                    LISTEN      9487/etcd
tcp6       0      0 :::6443                 :::*                    LISTEN      9133/kube-apiserver
tcp6       0      0 :::2380                 :::*                    LISTEN      9487/etcd
...
```
> 若看到以上資訊表示服務正常啟動，若發生問題可以用`docker`指令來查看。

接下來將建立 TLS Bootstrapping 來讓 Node 簽證並授權註冊到叢集。

### 建立 TLS Bootstrapping
由於本教學採用 TLS 認證來確保 Kubernetes 叢集的安全性，因此每個節點的 kubelet 都需要透過 API Server 的 CA 進行身份驗證後，才能與 API Server 進行溝通，而這過程過去都是採用手動方式針對每台節點(`master`與`node`)單獨簽署憑證，再設定給 kubelet 使用，然而這種方式是一件繁瑣的事情，因為當節點擴展到一定程度時，將會非常費時，甚至延伸初管理不易問題。

而由於上述問題，Kubernetes 實現了 TLS Bootstrapping 來解決此問題，這種做法是先讓 kubelet 以一個低權限使用者(一個能存取 CSR API 的 Token)存取 API Server，接著對 API Server 提出申請憑證簽署請求，並在受理後由 API Server 動態簽署 kubelet 憑證提供給對應的`node`節點使用。具體作法請參考 [TLS Bootstrapping](https://kubernetes.io/docs/admin/kubelet-tls-bootstrapping/) 與 [Authenticating with Bootstrap Tokens](https://kubernetes.io/docs/admin/bootstrap-tokens/)。

在`k8s-m1`建立 bootstrap 使用者的 kubeconfig 檔：
```sh
$ export TOKEN_ID=$(openssl rand 3 -hex)
$ export TOKEN_SECRET=$(openssl rand 8 -hex)
$ export BOOTSTRAP_TOKEN=${TOKEN_ID}.${TOKEN_SECRET}
$ export KUBE_APISERVER="https://172.22.132.9:6443"

$ kubectl config set-cluster kubernetes \
    --certificate-authority=/etc/kubernetes/pki/ca.pem \
    --embed-certs=true \
    --server=${KUBE_APISERVER} \
    --kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf

$ kubectl config set-credentials tls-bootstrap-token-user \
    --token=${BOOTSTRAP_TOKEN} \
    --kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf

$ kubectl config set-context tls-bootstrap-token-user@kubernetes \
    --cluster=kubernetes \
    --user=tls-bootstrap-token-user \
    --kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf

$ kubectl config use-context tls-bootstrap-token-user@kubernetes \
    --kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf
```
> `KUBE_APISERVER`這邊設定為 VIP 位址。若想要用手動簽署憑證來進行授權的話，可以參考 [Certificate](https://kubernetes.io/docs/concepts/cluster-administration/certificates/)。

接著在`k8s-m1`建立 TLS Bootstrap Secret 來提供自動簽證使用：
```sh
$ cat <<EOF | kubectl create -f -
apiVersion: v1
kind: Secret
metadata:
  name: bootstrap-token-${TOKEN_ID}
  namespace: kube-system
type: bootstrap.kubernetes.io/token
stringData:
  token-id: "${TOKEN_ID}"
  token-secret: "${TOKEN_SECRET}"
  usage-bootstrap-authentication: "true"
  usage-bootstrap-signing: "true"
  auth-extra-groups: system:bootstrappers:default-node-token
EOF

secret "bootstrap-token-65a3a9" created
```

然後建立 TLS Bootstrap Autoapprove RBAC 來提供自動受理 CSR：
```sh
$ kubectl apply -f master/resources/kubelet-bootstrap-rbac.yml
clusterrolebinding.rbac.authorization.k8s.io/kubelet-bootstrap created
clusterrolebinding.rbac.authorization.k8s.io/node-autoapprove-bootstrap created
clusterrolebinding.rbac.authorization.k8s.io/node-autoapprove-certificate-rotation created
```

### 驗證 Master 節點
完成後，在任意一台`master`節點複製 Admin kubeconfig 檔案，並透過簡單指令驗證：
```sh
$ cp /etc/kubernetes/admin.conf ~/.kube/config
$ kubectl get cs
NAME                 STATUS    MESSAGE             ERROR
scheduler            Healthy   ok
controller-manager   Healthy   ok
etcd-0               Healthy   {"health":"true"}
etcd-1               Healthy   {"health":"true"}
etcd-2               Healthy   {"health":"true"}

$ kubectl -n kube-system get po
NAME                             READY     STATUS    RESTARTS   AGE
etcd-k8s-m1                      1/1       Running   0          1h
etcd-k8s-m2                      1/1       Running   0          1h
etcd-k8s-m3                      1/1       Running   0          1h
kube-apiserver-k8s-m1            1/1       Running   0          1h
kube-apiserver-k8s-m2            1/1       Running   0          1h
kube-apiserver-k8s-m3            1/1       Running   0          1h
...

$ kubectl get node
NAME      STATUS     ROLES     AGE       VERSION
k8s-m1    NotReady   master    38s       v1.11.0
k8s-m2    NotReady   master    37s       v1.11.0
k8s-m3    NotReady   master    36s       v1.11.0
```
> 在這階段狀態處於`NotReady`是正常，往下進行就會了解為何。

透過 kubectl logs 來查看容器的日誌：
```sh
$ kubectl -n kube-system logs -f kube-apiserver-k8s-m1
Error from server (Forbidden): Forbidden (user=kube-apiserver, verb=get, resource=nodes, subresource=proxy) ( pods/log kube-apiserver-k8s-m1)
```
> 這邊會發現出現 403 Forbidden 問題，這是因為 `kube-apiserver` user 並沒有 nodes 的資源存取權限，屬於正常。

為了方便管理叢集，因此需要透過 kubectl logs 來查看，但由於 API 權限問題，故需要建立一個  RBAC Role 來獲取存取權限，這邊在`k8s-m1`節點執行以下指令建立：
```sh
$ kubectl apply -f master/resources/apiserver-to-kubelet-rbac.yml
clusterrole.rbac.authorization.k8s.io/system:kube-apiserver-to-kubelet created
clusterrolebinding.rbac.authorization.k8s.io/system:kube-apiserver created
```

完成後，再次透過 kubectl logs 查看 Pod：
```sh
$ kubectl -n kube-system logs -f kube-apiserver-k8s-m1
I0708 15:22:33.906269       1 get.go:245] Starting watch for /api/v1/services, rv=2494 labels= fields= timeout=8m29s
I0708 15:22:40.919638       1 get.go:245] Starting watch for /apis/certificates.k8s.io/v1beta1/certificatesigningrequests, rv=11084 labels= fields= timeout=7m29s
...
```

接著設定 [Taints and Tolerations](https://kubernetes.io/docs/concepts/configuration/taint-and-toleration/) 來讓一些特定 Pod 能夠排程到所有`master`節點上：
```sh
$ kubectl taint nodes node-role.kubernetes.io/master="":NoSchedule --all
node "k8s-m1" tainted
node "k8s-m2" tainted
node "k8s-m3" tainted
```

截至這邊已完成`master`節點部署，接下來將針對`node`的部署進行說明。

## Kubernetes Nodes
本節將說明如何建立與設定 Kubernetes Node 節點，Node 是主要執行容器實例(Pod)的工作節點。這過程只需要將 PKI、Bootstrap conf 等檔案複製到機器上，再用 kubelet 啟動即可。

在開始部署前，在`k8-m1`將需要用到的檔案複製到所有`node`節點上：
```sh
$ for NODE in k8s-g1 k8s-g2; do
    echo "--- $NODE ---"
    ssh ${NODE} "mkdir -p /etc/kubernetes/pki/"
    for FILE in pki/ca.pem pki/ca-key.pem bootstrap-kubelet.conf; do
      scp /etc/kubernetes/${FILE} ${NODE}:/etc/kubernetes/${FILE}
    done
  done
```

### 部署與設定
確認檔案都複製後，即可設定所有`node`節點的 kubelet systemd 來啟動 Kubernetes 元件。首先在`k8s-m1`複製下列檔案到指定路徑：
```sh
$ cd ~/k8s-manual-files
$ for NODE in k8s-g1 k8s-g2; do
    echo "--- $NODE ---"
    ssh ${NODE} "mkdir -p /var/lib/kubelet /var/log/kubernetes /var/lib/etcd /etc/systemd/system/kubelet.service.d /etc/kubernetes/manifests"
    scp node/var/lib/kubelet/config.yml ${NODE}:/var/lib/kubelet/config.yml
    scp node/systemd/kubelet.service ${NODE}:/lib/systemd/system/kubelet.service
    scp node/systemd/10-kubelet.conf ${NODE}:/etc/systemd/system/kubelet.service.d/10-kubelet.conf
  done
```

接著在`k8s-m1`透過 SSH 啟動所有`node`節點的 kubelet：
```sh
$ for NODE in k8s-g1 k8s-g2; do
    ssh ${NODE} "systemctl enable kubelet.service && systemctl start kubelet.service"
  done
```

### 驗證 Node 節點
完成後，在任意一台`master`節點複製 Admin kubeconfig 檔案，並透過簡單指令驗證：
```sh
$ kubectl get csr
NAME                                                   AGE       REQUESTOR                 CONDITION
csr-99n76                                              1h        system:node:k8s-m2        Approved,Issued
csr-9n88h                                              1h        system:node:k8s-m1        Approved,Issued
csr-vdtqr                                              1h        system:node:k8s-m3        Approved,Issued
node-csr-5VkCjWvb8tGVtO-d2gXiQrnst-G1xe_iA0AtQuYNEMI   2m        system:bootstrap:872255   Approved,Issued
node-csr-Uwpss9OhJrAgOB18P4OIEH02VHJwpFrSoMOWkkrK-lo   2m        system:bootstrap:872255   Approved,Issued

$ kubectl get nodes
NAME      STATUS     ROLES     AGE       VERSION
k8s-g1    NotReady   <none>    8m        v1.11.0
k8s-g2    NotReady   <none>    8m        v1.11.0
k8s-m1    NotReady   master    20m       v1.11.0
k8s-m2    NotReady   master    20m       v1.11.0
k8s-m3    NotReady   master    20m       v1.11.0
```
> 在這階段狀態處於`NotReady`是正常，往下進行就會了解為何。

到這邊就表示`node`節點部署已完成了，接下來章節將針對 Kubernetes Addons 安裝進行說明。

## Kubernetes Core Addons 部署
當完成`master`與`node`節點的部署，並組合成一個可運作叢集後，就可以開始透過 kubectl 部署 Addons，Kubernetes 官方提供了多種 Addons 來加強 Kubernetes 的各種功能，如叢集 DNS 解析的`kube-dns(or CoreDNS)`、外部存取服務的`kube-proxy`與 Web-based 管理介面的`dashboard`等等。而其中有些 Addons 是被 Kubernetes 認定為必要的，因此本節將說明如何部署這些 Addons。

首先在`k8s-m1`節點進入`k8s-manual-files`目錄，並依序執行下述指令來完成部署：
```sh
$ cd ~/k8s-manual-files
```

### Kubernetes Proxy
[kube-proxy](https://github.com/kubernetes/kubernetes/tree/master/cluster/addons/kube-proxy) 是實現 Kubernetes Service 資源功能的關鍵元件，這個元件會透過 DaemonSet 在每台節點上執行，然後監聽 API Server 的 Service 與 Endpoint 資源物件的事件，並依據資源預期狀態透過 iptables 或 ipvs 來實現網路轉發，而本次安裝採用 ipvs。

在`k8s-m1`透過 kubeclt 執行下面指令來建立，並檢查是否部署成功：
```sh
$ export KUBE_APISERVER=https://172.22.132.9:6443
$ sed -i "s/\${KUBE_APISERVER}/${KUBE_APISERVER}/g" addons/kube-proxy/kube-proxy-cm.yml
$ kubectl -f addons/kube-proxy/

$ kubectl -n kube-system get po -l k8s-app=kube-proxy
NAME               READY     STATUS    RESTARTS   AGE
kube-proxy-dd2m7   1/1       Running   0          8m
kube-proxy-fwgx8   1/1       Running   0          8m
kube-proxy-kjn57   1/1       Running   0          8m
kube-proxy-vp47w   1/1       Running   0          8m
kube-proxy-xsncw   1/1       Running   0          8m

# 檢查 log 是否使用 ipvs
$ kubectl -n kube-system logs -f kube-proxy-fwgx8
I0709 08:41:48.220815       1 feature_gate.go:230] feature gates: &{map[SupportIPVSProxyMode:true]}
I0709 08:41:48.231009       1 server_others.go:183] Using ipvs Proxier.
...
```

若有安裝 ipvsadm 的話，可以透過以下指令查看 proxy 規則：
```sh
$ ipvsadm -ln
IP Virtual Server version 1.2.1 (size=4096)
Prot LocalAddress:Port Scheduler Flags
  -> RemoteAddress:Port           Forward Weight ActiveConn InActConn
TCP  10.96.0.1:443 rr
  -> 172.22.132.9:5443            Masq    1      0          0
```

### CoreDNS
本節將透過 CoreDNS 取代 [Kube DNS](https://github.com/kubernetes/kubernetes/tree/master/cluster/addons/dns) 作為叢集服務發現元件，由於 Kubernetes 需要讓 Pod 與 Pod 之間能夠互相溝通，然而要能夠溝通需要知道彼此的 IP 才行，而這種做法通常是透過 Kubernetes API 來取得達到，但是 Pod IP 會因為生命週期變化而改變，因此這種做法無法彈性使用，且還會增加 API Server 負擔，基於此問題 Kubernetes 提供了 DNS 服務來作為查詢，讓 Pod 能夠以 Service 名稱作為域名來查詢 IP 位址，因此使用者就再不需要關切實際 Pod IP，而 DNS 也會根據 Pod 變化更新資源紀錄(Record resources)。

[CoreDNS](https://github.com/coredns/coredns) 是由 CNCF 維護的開源 DNS 專案，該專案前身是 SkyDNS，其採用了 Caddy 的一部分來開發伺服器框架，使其能夠建構一套快速靈活的 DNS，而 CoreDNS 每個功能都可以被實作成一個插件的中介軟體，如 Log、Cache、Kubernetes 等功能，甚至能夠將源紀錄儲存至 Redis、Etcd 中。

在`k8s-m1`透過 kubeclt 執行下面指令來建立，並檢查是否部署成功：
```sh
$ kubectl create -f addons/coredns/

$ kubectl -n kube-system get po -l k8s-app=kube-dns
NAME                       READY     STATUS    RESTARTS   AGE
coredns-589dd74cb6-5mv5c   0/1       Pending   0          3m
coredns-589dd74cb6-d42ft   0/1       Pending   0          3m
```

這邊會發現 Pod 處於`Pending`狀態，這是由於 Kubernetes 的叢集網路沒有建立，因此所有節點會處於`NotReady`狀態，而這也導致 Kubernetes Scheduler 無法替 Pod 找到適合節點而處於`Pending`，為了解決這個問題，下節將說明與建立 Kubernetes 叢集網路。
> 若 Pod 是被 DaemonSet 管理，且設定使用`hostNetwork`的話，則不會處於`Pending`狀態。

## Kubernetes 叢集網路
Kubernetes 在預設情況下與 Docker 的網路有所不同。在 Kubernetes 中有四個問題是需要被解決的，分別為：

* **高耦合的容器到容器溝通**：透過 Pods 與 Localhost 的溝通來解決。
* **Pod 到 Pod 的溝通**：透過實現網路模型來解決。
* **Pod 到 Service 溝通**：由 Service objects 結合 kube-proxy 解決。
* **外部到 Service 溝通**：一樣由 Service objects 結合 kube-proxy 解決。

而 Kubernetes 對於任何網路的實現都需要滿足以下基本要求(除非是有意調整的網路分段策略)：

* 所有容器能夠在沒有 NAT 的情況下與其他容器溝通。
* 所有節點能夠在沒有 NAT 情況下與所有容器溝通(反之亦然)。
* 容器看到的 IP 與其他人看到的 IP 是一樣的。

慶幸的是 Kubernetes 已經有非常多種的[網路模型](https://kubernetes.io/docs/concepts/cluster-administration/networking/#how-to-implement-the-kubernetes-networking-model)以[網路插件(Network Plugins)](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/)方式被實現，因此可以選用滿足自己需求的網路功能來使用。另外 Kubernetes 中的網路插件有以下兩種形式：

* **CNI plugins**：以 appc/CNI 標準規範所實現的網路，詳細可以閱讀 [CNI Specification](https://github.com/containernetworking/cni/blob/master/SPEC.md)。
* **Kubenet plugin**：使用 CNI plugins 的 bridge 與 host-local 來實現基本的 cbr0。這通常被用在公有雲服務上的 Kubernetes 叢集網路。

> 如果想了解如何選擇可以閱讀 Chris Love 的 [Choosing a CNI Network Provider for Kubernetes](https://chrislovecnm.com/kubernetes/cni/choosing-a-cni-provider/) 文章。

### 網路部署與設定
從上述了解 Kubernetes 有多種網路能夠選擇，而本教學選擇了 [Calico](https://www.projectcalico.org/) 作為叢集網路的使用。Calico 是一款純 Layer 3 的網路，其好處是它整合了各種雲原生平台(Docker、Mesos 與 OpenStack 等)，且 Calico 不採用 vSwitch，而是在每個 Kubernetes 節點使用 vRouter 功能，並透過 Linux Kernel 既有的 L3 forwarding 功能，而當資料中心複雜度增加時，Calico 也可以利用 BGP route reflector 來達成。
> 想了解 Calico 與傳統 overlay networks 的差異，可以閱讀 [Difficulties with traditional overlay networks](https://www.projectcalico.org/learn/) 文章。

由於 Calico 提供了 Kubernetes resources YAML 檔來快速以容器方式部署網路插件至所有節點上，因此只需要在`k8s-m1`透過 kubeclt 執行下面指令來建立：
```sh
$ cd ~/k8s-manual-files
$ sed -i 's/192.168.0.0\/16/10.244.0.0\/16/g' cni/calico/v3.1/calico.yaml
$ kubectl -f cni/calico/v3.1/
```
> * 這邊要記得將`CALICO_IPV4POOL_CIDR`的網路修改 Cluster IP CIDR。
> * 另外當節點超過 50 台，可以使用 Calico 的 [Typha](https://github.com/projectcalico/typha) 模式來減少透過 Kubernetes datastore 造成 API Server 的負擔。

部署後透過 kubectl 檢查是否有啟動：
```sh
$ kubectl -n kube-system get po -l k8s-app=calico-node
NAME                READY     STATUS    RESTARTS   AGE
calico-node-27jwl   2/2       Running   0          59s
calico-node-4fgv6   2/2       Running   0          59s
calico-node-mvrt7   2/2       Running   0          59s
calico-node-p2q9g   2/2       Running   0          59s
calico-node-zchsz   2/2       Running   0          59s
```

確認 calico-node 都正常運作後，透過 kubectl exec 進入 calicoctl pod 來檢查功能是否正常：
```sh
$ kubectl exec -ti -n kube-system calicoctl -- calicoctl get profiles -o wide
NAME              LABELS
kns.default       map[]
kns.kube-public   map[]
kns.kube-system   map[]

$ kubectl exec -ti -n kube-system calicoctl -- calicoctl get node -o wide
NAME     ASN         IPV4               IPV6
k8s-g1   (unknown)   172.22.132.13/24
k8s-g2   (unknown)   172.22.132.14/24
k8s-m1   (unknown)   172.22.132.10/24
k8s-m2   (unknown)   172.22.132.11/24
k8s-m3   (unknown)   172.22.132.12/24
```
> 若沒問題，就可以將 kube-system 下的 calicoctl pod 刪除。

完成後，透過檢查節點是否不再是`NotReady`，以及 Pod 是否不再處於`Pending`：
```sh
$ kubectl get no
NAME      STATUS    ROLES     AGE       VERSION
k8s-g1    Ready     <none>    35m       v1.11.0
k8s-g2    Ready     <none>    35m       v1.11.0
k8s-m1    Ready     master    35m       v1.11.0
k8s-m2    Ready     master    35m       v1.11.0
k8s-m3    Ready     master    35m       v1.11.0

$ kubectl -n kube-system get po -l k8s-app=kube-dns -o wide
NAME                       READY     STATUS    RESTARTS   AGE       IP           NODE
coredns-589dd74cb6-5mv5c   1/1       Running   0          10m       10.244.4.2   k8s-g2
coredns-589dd74cb6-d42ft   1/1       Running   0          10m       10.244.3.2   k8s-g1
```

當成功到這邊時，一個能運作的 Kubernetes 叢集基本上就完成了，接下來將介紹一些好用的 Addons 來幫助使用與管理 Kubernetes。

## Kubernetes Extra Addons 部署
本節說明如何部署一些官方常用的額外 Addons，如 Dashboard、Metrics Server 與 Ingress Controller 等等。

所有 Addons 部署檔案均存已放至`k8s-manual-files`中，因此在`k8s-m1`進入該目錄，並依序下小節建立：
```sh
$ cd ~/k8s-manual-files
```

### Ingress Controller
[Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) 是 Kubernetes 中的一個抽象資源，其功能是透過 Web Server 的 Virtual Host 概念以域名(Domain Name)方式轉發到內部 Service，這避免了使用 Service 中的 NodePort 與 LoadBalancer 類型所帶來的限制(如 Port 數量上限)，而實現 Ingress 功能則是透過 [Ingress Controller](https://kubernetes.io/docs/concepts/services-networking/ingress/#ingress-controllers) 來達成，它會負責監聽 Kubernetes API 中的 Ingress 與 Service 資源物件，並在發生資源變化時，依據資源預期的結果來設定 Web Server。另外 Ingress Controller 有許多實現可以選擇：

- [Ingress NGINX](https://github.com/kubernetes/ingress-nginx): Kubernetes 官方維護的專案，也是本次安裝使用的 Controller。
- [F5 BIG-IP Controller](https://clouddocs.f5.com/products/connectors/k8s-bigip-ctlr/v1.5/): F5 所開發的 Controller，它能夠讓管理員透過 CLI 或 API 從 Kubernetes 與 OpenShift 管理 F5 BIG-IP 設備。
- [Ingress Kong](https://konghq.com/blog/kubernetes-ingress-controller-for-kong/): 著名的開源 API Gateway 專案所維護的 Kubernetes Ingress Controller。
- [Træfik](https://github.com/containous/traefik): 是一套開源的 HTTP 反向代理與負載平衡器，而它也支援了 Ingress。
- [Voyager](https://github.com/appscode/voyager): 一套以 HAProxy 為底的 Ingress Controller。

> 而 Ingress Controller 的實現不只這些專案，還有很多可以在網路上找到，未來自己也會寫一篇 Ingress Controller 的實作方式文章。

首先在`k8s-m1`執行下述指令來建立 Ingress Controller，並檢查是否部署正常：
```sh
$ export INGRESS_VIP=172.22.132.8
$ sed -i "s/\${INGRESS_VIP}/${INGRESS_VIP}/g" addons/ingress-controller/ingress-controller-svc.yml
$ kubectl create ns ingress-nginx
$ kubectl apply -f addons/ingress-controller
$ kubectl -n ingress-nginx get po,svc
NAME                                           READY     STATUS    RESTARTS   AGE
pod/default-http-backend-846b65fb5f-l5hrc      1/1       Running   0          2m
pod/nginx-ingress-controller-5db8d65fb-z2lf9   1/1       Running   0          2m

NAME                           TYPE           CLUSTER-IP      EXTERNAL-IP    PORT(S)        AGE
service/default-http-backend   ClusterIP      10.99.105.112   <none>         80/TCP         2m
service/ingress-nginx          LoadBalancer   10.106.18.106   172.22.132.8   80:31197/TCP   2m
```

完成後透過瀏覽器存取 http://172.22.132.8:80 來查看是否能連線，若可以會如下圖結果。

![](https://i.imgur.com/CfbLwOP.png)

當確認上面步驟都沒問題後，就可以透過 kubeclt 建立簡單 NGINX 來測試功能：
```sh
$ kubectl apply -f apps/nginx/
deployment.extensions/nginx created
ingress.extensions/nginx-ingress created
service/nginx created

$ kubectl get po,svc,ing
NAME                        READY     STATUS    RESTARTS   AGE
pod/nginx-966857787-78kth   1/1       Running   0          32s

NAME                 TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)   AGE
service/kubernetes   ClusterIP   10.96.0.1        <none>        443/TCP   2d
service/nginx        ClusterIP   10.104.180.119   <none>        80/TCP    32s

NAME                               HOSTS             ADDRESS        PORTS     AGE
ingress.extensions/nginx-ingress   nginx.k8s.local   172.22.132.8   80        33s
```
> P.S. Ingress 規則也支援不同 Path 的服務轉發，可以參考上面提供的官方文件來設定。

完成後透過 cURL 工具來測試功能是否正常：
```sh
$ curl 172.22.132.8 -H 'Host: nginx.k8s.local'
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
...

# 測試其他 domain name 是否會回傳 404
$ curl 172.22.132.8 -H 'Host: nginx1.k8s.local'
default backend - 404
```

雖然 Ingress 能夠讓我們透過域名方式存取 Kubernetes 內部服務，但是若域名於法被測試機器解析的話，將會顯示`default backend - 404`結果，而這經常發生在內部自建環境上，雖然可以透過修改主機`/etc/hosts`來描述，但並不彈性，因此下節將說明如何建立一個 External DNS 與 DNS 伺服器來提供自動解析 Ingress 域名。

### External DNS
[External DNS](https://github.com/kubernetes-incubator/external-dns) 是 Kubernetes 社區的孵化專案，被用於定期同步 Kubernetes Service 與 Ingress 資源，並依據資源內容來自動設定公有雲 DNS 服務的資源紀錄(Record resources)。而由於部署不是公有雲環境，因此需要透過 CoreDNS 提供一個內部 DNS 伺服器，再由 ExternalDNS 與這個 CoreDNS 做串接。

首先在`k8s-m1`執行下述指令來建立 CoreDNS Server，並檢查是否部署正常：
```sh
$ export DNS_VIP=172.22.132.8
$ sed -i "s/\${DNS_VIP}/${DNS_VIP}/g" addons/external-dns/coredns/coredns-svc-tcp.yml
$ sed -i "s/\${DNS_VIP}/${DNS_VIP}/g" addons/external-dns/coredns/coredns-svc-udp.yml
$ kubectl create -f addons/external-dns/coredns/
$ kubectl -n external-dns get po,svc
NAME                                READY     STATUS    RESTARTS   AGE
pod/coredns-54bcfcbd5b-5grb5        1/1       Running   0          2m
pod/coredns-etcd-6c9c68fd76-n8rhj   1/1       Running   0          2m

NAME                   TYPE           CLUSTER-IP       EXTERNAL-IP    PORT(S)                       AGE
service/coredns-etcd   ClusterIP      10.110.186.83    <none>         2379/TCP,2380/TCP             2m
service/coredns-tcp    LoadBalancer   10.109.105.166   172.22.132.8   53:32169/TCP,9153:32150/TCP   2m
service/coredns-udp    LoadBalancer   10.110.242.185   172.22.132.8   53:31210/UDP
```
> 這邊域名為`k8s.local`，可以修改檔案中的`coredns-cm.yml`來改變。

完成後，透過 dig 工具來檢查是否 DNS 是否正常：
```
$ dig @172.22.132.8 SOA nginx.k8s.local +noall +answer +time=2 +tries=1
...
; (1 server found)
;; global options: +cmd
k8s.local.		300	IN	SOA	ns.dns.k8s.local. hostmaster.k8s.local. 1531299150 7200 1800 86400 30
```

接著部署 ExternalDNS 來與 CoreDNS 同步資源紀錄：
```sh
$ kubectl apply -f addons/external-dns/external-dns/
$ kubectl -n external-dns get po -l k8s-app=external-dns
NAME                            READY     STATUS    RESTARTS   AGE
external-dns-86f67f6df8-ljnhj   1/1       Running   0          1m
```

完成後，透過 dig 與 nslookup 工具檢查上節測試 Ingress 的 NGINX 服務：
```
$ dig @172.22.132.8 A nginx.k8s.local +noall +answer +time=2 +tries=1
...
; (1 server found)
;; global options: +cmd
nginx.k8s.local.	300	IN	A	172.22.132.8

$ nslookup nginx.k8s.local
Server:		172.22.132.8
Address:	172.22.132.8#53

** server can't find nginx.k8s.local: NXDOMAIN
```

這時會無法透過 nslookup 解析域名，這是因為測試機器並沒有使用這個 DNS 伺服器，可以透過修改`/etc/resolv.conf`來加入，或者類似下圖方式(不同 OS 有差異，不過都在網路設定中改)。

![](https://i.imgur.com/MVDhXKi.png)

再次透過 nslookup 檢查，會發現可以解析了，這時也就能透過 cURL 來測試結果：
```sh
$ nslookup nginx.k8s.local
Server:		172.22.132.8
Address:	172.22.132.8#53

Name:	nginx.k8s.local
Address: 172.22.132.8

$ curl nginx.k8s.local
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
...
```

### Dashboard
[Dashboard](https://github.com/kubernetes/dashboard) 是 Kubernetes 官方開發的 Web-based 儀表板，目的是提升管理 Kubernetes 叢集資源便利性，並以資源視覺化方式，來讓人更直覺的看到整個叢集資源狀態，

在`k8s-m1`透過 kubeclt 執行下面指令來建立 Dashboard 至 Kubernetes，並檢查是否正確部署：
```sh
$ cd ~/k8s-manual-files
$ kubectl apply -f addons/dashboard/
$ kubectl -n kube-system get po,svc -l k8s-app=kubernetes-dashboard
NAME                                       READY     STATUS    RESTARTS   AGE
pod/kubernetes-dashboard-6948bdb78-w26qc   1/1       Running   0          2m

NAME                           TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
service/kubernetes-dashboard   ClusterIP   10.109.31.80   <none>        443/TCP   2m
```

在這邊會額外建立名稱為`anonymous-dashboard-proxy`的 Cluster Role(Binding) 來讓`system:anonymous`這個匿名使用者能夠透過 API Server 來 proxy 到 Kubernetes Dashboard，而這個 RBAC 規則僅能夠存取`services/proxy`資源，以及`https:kubernetes-dashboard:`資源名稱。

因此我們能夠在完成後，透過以下連結來進入 Kubernetes Dashboard：
- [https://{YOUR_VIP}:6443/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/](https://YOUR_VIP:6443/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/)

由於 Kubernetes Dashboard v1.7 版本以後不再提供 Admin 權限，因此需要透過 kubeconfig 或者 Service Account 來進行登入才能取得資源來呈現，這邊建立一個 Service Account 來綁定`cluster-admin` 以測試功能：
```sh
$ kubectl -n kube-system create sa dashboard
$ kubectl create clusterrolebinding dashboard --clusterrole cluster-admin --serviceaccount=kube-system:dashboard
$ SECRET=$(kubectl -n kube-system get sa dashboard -o yaml | awk '/dashboard-token/ {print $3}')
$ kubectl -n kube-system describe secrets ${SECRET} | awk '/token:/{print $2}'
eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJrdWJlcm5ldGVzL3NlcnZpY2VhY2NvdW50Iiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9uYW1lc3BhY2UiOiJrdWJlLXN5c3RlbSIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VjcmV0Lm5hbWUiOiJkYXNoYm9hcmQtdG9rZW4tdzVocmgiLCJrdWJlcm5ldGVzLmlvL3NlcnZpY2VhY2NvdW50L3NlcnZpY2UtYWNjb3VudC5uYW1lIjoiZGFzaGJvYXJkIiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9zZXJ2aWNlLWFjY291bnQudWlkIjoiYWJmMTFjYzMtZjRlYi0xMWU3LTgzYWUtMDgwMDI3NjdkOWI5Iiwic3ViIjoic3lzdGVtOnNlcnZpY2VhY2NvdW50Omt1YmUtc3lzdGVtOmRhc2hib2FyZCJ9.Xuyq34ci7Mk8bI97o4IldDyKySOOqRXRsxVWIJkPNiVUxKT4wpQZtikNJe2mfUBBD-JvoXTzwqyeSSTsAy2CiKQhekW8QgPLYelkBPBibySjBhJpiCD38J1u7yru4P0Pww2ZQJDjIxY4vqT46ywBklReGVqY3ogtUQg-eXueBmz-o7lJYMjw8L14692OJuhBjzTRSaKW8U2MPluBVnD7M2SOekDff7KpSxgOwXHsLVQoMrVNbspUCvtIiEI1EiXkyCNRGwfnd2my3uzUABIHFhm0_RZSmGwExPbxflr8Fc6bxmuz-_jSdOtUidYkFIzvEWw2vRovPgs3MXTv59RwUw
```
> 複製`token`然後貼到 Kubernetes dashboard。注意這邊一般來說要針對不同 User 開啟特定存取權限。

![](/images/kube/kubernetes-dashboard.png)

### Prometheus
由於 [Heapster](https://github.com/kubernetes/heapster/blob/master/docs/deprecation.md) 將要被移棄，因此這邊選用 [Prometheus](https://prometheus.io/) 作為第三方的叢集監控方案。而本次安裝採用 CoreOS 開發的 [Prometheus Operator](https://github.com/coreos/prometheus-operator) 用於管理在 Kubernetes 上的 Prometheus 叢集與資源，更多關於 Prometheus Operator 的資訊可以參考小弟的 [Prometheus Operator 介紹與安裝](https://kairen.github.io/2018/06/23/devops/prometheus-operator/) 文章。

首先在`k8s-m1`執行下述指令來部署所有 Prometheus 需要的元件：
```sh
$ kubectl apply -f addons/prometheus/
$ kubectl apply -f addons/prometheus/operator/

# 這邊要等 operator 起來並建立好 CRDs 才能進行
$ kubectl apply -f addons/prometheus/alertmanater/
$ kubectl apply -f addons/prometheus/node-exporter/
$ kubectl apply -f addons/prometheus/kube-state-metrics/
$ kubectl apply -f addons/prometheus/grafana/
$ kubectl apply -f addons/prometheus/kube-service-discovery/
$ kubectl apply -f addons/prometheus/prometheus/
$ kubectl apply -f addons/prometheus/servicemonitor/
```

完成後，透過 kubectl 檢查服務是否正常運行：
```sh
$ kubectl -n monitoring get po,svc,ing
NAME                                      READY     STATUS    RESTARTS   AGE
pod/alertmanager-main-0                   1/2       Running   0          1m
pod/grafana-6d495c46d5-jpf6r              1/1       Running   0          43s
pod/kube-state-metrics-b84cfb86-4b8qg     4/4       Running   0          37s
pod/node-exporter-2f4lh                   2/2       Running   0          59s
pod/node-exporter-7cz5s                   2/2       Running   0          59s
pod/node-exporter-djdtk                   2/2       Running   0          59s
pod/node-exporter-kfpzt                   2/2       Running   0          59s
pod/node-exporter-qp2jf                   2/2       Running   0          59s
pod/prometheus-k8s-0                      3/3       Running   0          28s
pod/prometheus-k8s-1                      3/3       Running   0          15s
pod/prometheus-operator-9ffd6bdd9-rvqsz   1/1       Running   0          1m

NAME                            TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)             AGE
service/alertmanager-main       ClusterIP   10.110.188.2     <none>        9093/TCP            1m
service/alertmanager-operated   ClusterIP   None             <none>        9093/TCP,6783/TCP   1m
service/grafana                 ClusterIP   10.104.147.154   <none>        3000/TCP            43s
service/kube-state-metrics      ClusterIP   None             <none>        8443/TCP,9443/TCP   51s
service/node-exporter           ClusterIP   None             <none>        9100/TCP            1m
service/prometheus-k8s          ClusterIP   10.96.78.58      <none>        9090/TCP            28s
service/prometheus-operated     ClusterIP   None             <none>        9090/TCP            33s
service/prometheus-operator     ClusterIP   10.99.251.16     <none>        8080/TCP            1m

NAME                                HOSTS                             ADDRESS        PORTS     AGE
ingress.extensions/grafana-ing      grafana.monitoring.k8s.local      172.22.132.8   80        45s
ingress.extensions/prometheus-ing   prometheus.monitoring.k8s.local   172.22.132.8   80        34s
```

確認沒問題後，透過瀏覽器查看 [prometheus.monitoring.k8s.local](http://prometheus.monitoring.k8s.local) 與 [grafana.monitoring.k8s.local](http://grafana.monitoring.k8s.local) 是否正常，若沒問題就可以看到如下圖所示結果。

![](https://i.imgur.com/XFTZ4eF.png)

![](https://i.imgur.com/YB5KAPe.png)

> 另外這邊也推薦用 [Weave Scope](https://github.com/weaveworks/scope) 來監控容器的網路 Flow 拓樸圖。

### Metrics Server
[Metrics Server](https://github.com/kubernetes-incubator/metrics-server) 是實現了 Metrics API 的元件，其目標是取代 Heapster 作為 Pod 與 Node 提供資源的 Usage metrics，該元件會從每個 Kubernetes 節點上的 Kubelet 所公開的 Summary API 中收集 Metrics。

首先在`k8s-m1`測試一下 kubectl top 指令：
```sh
$ kubectl top node
error: metrics not available yet
```

發現 top 指令無法取得 Metrics，這表示 Kubernetes 叢集沒有安裝 Heapster 或是 Metrics Server 來提供 Metrics API 給 top 指令取得資源使用量。

由於上述問題，我們要在`k8s-m1`節點透過 kubectl 部署 Metrics Server 元件來解決：
```sh
$ kubectl create -f addons/metric-server/
$ kubectl -n kube-system get po -l k8s-app=metrics-server
NAME                                  READY     STATUS    RESTARTS   AGE
pod/metrics-server-86bd9d7667-5hbn6   1/1       Running   0          1m
```

完成後，等待一點時間(約 30s - 1m)收集 Metrics，再次執行 kubectl top 指令查看：
```sh
$ kubectl top node
NAME      CPU(cores)   CPU%      MEMORY(bytes)   MEMORY%
k8s-g1    106m         2%        1037Mi          6%
k8s-g2    212m         5%        1043Mi          8%
k8s-m1    386m         9%        2125Mi          13%
k8s-m2    320m         8%        1834Mi          11%
k8s-m3    457m         11%       1818Mi          11%
```

而這時若有使用 [HPA](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/) 的話，就能夠正確抓到 Pod 的 CPU 與 Memory 使用量了。
> 若想讓 HPA 使用 Prometheus 的 Metrics 的話，可以閱讀 [Custom Metrics Server](https://github.com/stefanprodan/k8s-prom-hpa#setting-up-a-custom-metrics-server) 來了解。

### Helm Tiller Server
[Helm](https://github.com/kubernetes/helm) 是 Kubernetes Chart 的管理工具，Kubernetes Chart 是一套預先組態的 Kubernetes 資源。其中`Tiller Server`主要負責接收來至 Client 的指令，並透過 kube-apiserver 與 Kubernetes 叢集做溝通，根據 Chart 定義的內容，來產生與管理各種對應 API 物件的 Kubernetes 部署檔案(又稱為 `Release`)。

首先在`k8s-m1`安裝 Helm tool：
```sh
$ wget -qO- https://kubernetes-helm.storage.googleapis.com/helm-v2.9.1-linux-amd64.tar.gz | tar -zx
$ sudo mv linux-amd64/helm /usr/local/bin/
```

另外在所有`node`節點安裝 socat：
```sh
$ sudo apt-get install -y socat
```

接著初始化 Helm(這邊會安裝 Tiller Server)：
```sh
$ kubectl -n kube-system create sa tiller
$ kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller
$ helm init --service-account tiller
...
Tiller (the Helm server-side component) has been installed into your Kubernetes Cluster.
Happy Helming!

$ kubectl -n kube-system get po -l app=helm
NAME                            READY     STATUS    RESTARTS   AGE
tiller-deploy-759cb9df9-rfhqw   1/1       Running   0          19s

$ helm version
Client: &version.Version{SemVer:"v2.9.1", GitCommit:"20adb27c7c5868466912eebdf6664e7390ebe710", GitTreeState:"clean"}
Server: &version.Version{SemVer:"v2.9.1", GitCommit:"20adb27c7c5868466912eebdf6664e7390ebe710", GitTreeState:"clean"}
```

#### 測試 Helm 功能
這邊部署簡單 Jenkins 來進行功能測試：
```sh
$ helm install --name demo --set Persistence.Enabled=false stable/jenkins
$ kubectl get po,svc  -l app=demo-jenkins
NAME                           READY     STATUS    RESTARTS   AGE
demo-jenkins-7bf4bfcff-q74nt   1/1       Running   0          2m

NAME                 TYPE           CLUSTER-IP       EXTERNAL-IP   PORT(S)          AGE
demo-jenkins         LoadBalancer   10.103.15.129    <pending>     8080:31161/TCP   2m
demo-jenkins-agent   ClusterIP      10.103.160.126   <none>        50000/TCP        2m

# 取得 admin 帳號的密碼
$ printf $(kubectl get secret --namespace default demo-jenkins -o jsonpath="{.data.jenkins-admin-password}" | base64 --decode);echo
r6y9FMuF2u
```

當服務都正常運作時，就可以透過瀏覽器查看 http://node_ip:31161 頁面。

![](/images/kube/helm-jenkins-v1.10.png)

測試完成後，就可以透過以下指令來刪除 Release：
```sh
$ helm ls
NAME	REVISION	UPDATED                 	STATUS  	CHART         	NAMESPACE
demo	1       	Tue Apr 10 07:29:51 2018	DEPLOYED	jenkins-0.14.4	default

$ helm delete demo --purge
release "demo" deleted
```

想要了解更多 Helm Apps 的話，可以到 [Kubeapps Hub](https://hub.kubeapps.com/) 網站尋找。

## 測試叢集 HA 功能
首先進入`k8s-m1`節點，然後關閉該節點：
```sh
$ sudo poweroff
```

接著進入到`k8s-m2`節點，透過 kubectl 來檢查叢集是否能夠正常執行：
```
# 先檢查 etcd 狀態，可以發現 etcd-0 因為關機而中斷
$ kubectl get cs
NAME                 STATUS      MESSAGE                                                                                                                                          ERROR
scheduler            Healthy     ok
controller-manager   Healthy     ok
etcd-1               Healthy     {"health": "true"}
etcd-2               Healthy     {"health": "true"}
etcd-0               Unhealthy   Get https://172.22.132.10:2379/health: net/http: request canceled while waiting for connection (Client.Timeout exceeded while awaiting headers)

# 測試是否可以建立 Pod
$ kubectl run nginx --image nginx --restart=Never --port 80
$ kubectl get po
NAME      READY     STATUS    RESTARTS   AGE
nginx     1/1       Running   0          22s
```
