---
title: Kubernetes v1.8.x 全手動苦工安裝教學(TL;DR)
date: 2017-10-27 17:08:54
layout: page
categories:
- Kubernetes
tags:
- Kubernetes
- Docker
- Calico
---
Kubernetes 提供了許多雲端平台與作業系統的安裝方式，本章將以`全手動安裝方式`來部署，主要是學習與了解 Kubernetes 建置流程。若想要瞭解更多平台的部署可以參考 [Picking the Right Solution](https://kubernetes.io/docs/getting-started-guides/)來選擇自己最喜歡的方式。

本次安裝版本為：
* Kubernetes v1.8.2
* Etcd v3.2.9
* Calico v2.6.2
* Docker v17.10.0-ce

<!--more-->

## 預先準備資訊
本教學將以下列節點數與規格來進行部署 Kubernetes 叢集，作業系統可採用`Ubuntu 16.x`與`CentOS 7.x`：

| IP Address  |   Role   |   CPU    |   Memory   |
|-------------|----------|----------|------------|
|172.16.35.12 |  master1 |    1     |     2G     |
|172.16.35.10 |  node1   |    1     |     2G     |
|172.16.35.11 |  node2   |    1     |     2G     |

> * 這邊 master 為主要控制節點也是`部署節點`，node 為應用程式工作節點。
> * 所有操作全部用`root`使用者進行(方便用)，以 SRE 來說不推薦。
> * 可以下載 [Vagrantfile](https://kairen.github.io/files/manual-v1.8/Vagrantfile) 來建立 Virtual box 虛擬機叢集。

首先安裝前要確認以下幾項都已將準備完成：
* 所有節點彼此網路互通，並且`master1` SSH 登入其他節點為 passwdless。
* 所有防火牆與 SELinux 已關閉。如 CentOS：

```sh
$ systemctl stop firewalld && systemctl disable firewalld
$ setenforce 0
$ vim /etc/selinux/config
SELINUX=disabled
```

* 所有節點需要設定`/etc/host`解析到所有主機。

```
...
172.16.35.10 node1
172.16.35.11 node2
172.16.35.12 master1
```

* 所有節點需要安裝`Docker`或`rtk`引擎。這邊採用`Docker`來當作容器引擎，安裝方式如下：

```sh
$ curl -fsSL "https://get.docker.com/" | sh
```
> 不管是在 `Ubuntu` 或 `CentOS` 都只需要執行該指令就會自動安裝最新版 Docker。
> CentOS 安裝完成後，需要再執行以下指令：
```sh
$ systemctl enable docker && systemctl start docker
```

編輯`/lib/systemd/system/docker.service`，在`ExecStart=..`上面加入：
```
ExecStartPost=/sbin/iptables -A FORWARD -s 0.0.0.0/0 -j ACCEPT
```
> 完成後，重新啟動 docker 服務：
```sh
$ systemctl daemon-reload && systemctl restart docker
```

* 所有節點需要設定`/etc/sysctl.d/k8s.conf`的系統參數。

```sh
$ cat <<EOF > /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

$ sysctl -p /etc/sysctl.d/k8s.conf
```

* 在`master1`需要安裝`CFSSL`工具，這將會用來建立 TLS certificates。

```sh
$ export CFSSL_URL="https://pkg.cfssl.org/R1.2"
$ wget "${CFSSL_URL}/cfssl_linux-amd64" -O /usr/local/bin/cfssl
$ wget "${CFSSL_URL}/cfssljson_linux-amd64" -O /usr/local/bin/cfssljson
$ chmod +x /usr/local/bin/cfssl /usr/local/bin/cfssljson
```

## Etcd
在開始安裝 Kubernetes 之前，需要先將一些必要系統建置完成，其中 Etcd 就是 Kubernetes 最重要的一環，Kubernetes 會將大部分資訊儲存於 Etcd 上，來提供給其他節點索取，以確保整個叢集運作與溝通正常。

### 建立叢集 CA 與 Certificates
在這部分，將會需要產生 client 與 server 的各元件 certificates，並且替 Kubernetes admin user 產生 client 證書。

建立`/etc/etcd/ssl`資料夾，然後進入目錄完成以下操作。
```sh
$ mkdir -p /etc/etcd/ssl && cd /etc/etcd/ssl
$ export PKI_URL="https://kairen.github.io/files/manual-v1.8/pki"
```

下載`ca-config.json`與`etcd-ca-csr.json`檔案，並產生 CA 金鑰：
```sh
$ wget "${PKI_URL}/ca-config.json" "${PKI_URL}/etcd-ca-csr.json"
$ cfssl gencert -initca etcd-ca-csr.json | cfssljson -bare etcd-ca
$ ls etcd-ca*.pem
etcd-ca-key.pem  etcd-ca.pem
```

下載`etcd-csr.json`檔案，並產生 etcd certificate 證書：
```sh
$ wget "${PKI_URL}/etcd-csr.json"
$ cfssl gencert \
  -ca=etcd-ca.pem \
  -ca-key=etcd-ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  etcd-csr.json | cfssljson -bare etcd

$ ls etcd*.pem
etcd-ca-key.pem  etcd-ca.pem  etcd-key.pem  etcd.pem
```
> 若節點 IP 不同，需要修改`etcd-csr.json`的`hosts`。

完成後刪除不必要檔案：
```sh
$ rm -rf *.json
```

確認`/etc/etcd/ssl`有以下檔案：
```sh
$ ls /etc/etcd/ssl
etcd-ca.csr  etcd-ca-key.pem  etcd-ca.pem  etcd.csr  etcd-key.pem  etcd.pem
```

### Etcd 安裝與設定
首先在`master1`節點下載 Etcd，並解壓縮放到 /opt 底下與安裝：
```sh
$ export ETCD_URL="https://github.com/coreos/etcd/releases/download"
$ cd && wget -qO- --show-progress "${ETCD_URL}/v3.2.9/etcd-v3.2.9-linux-amd64.tar.gz" | tar -zx
$ mv etcd-v3.2.9-linux-amd64/etcd* /usr/local/bin/ && rm -rf etcd-v3.2.9-linux-amd64
```

完成後新建 Etcd Group 與 User，並建立 Etcd 設定檔目錄：
```sh
$ groupadd etcd && useradd -c "Etcd user" -g etcd -s /sbin/nologin -r etcd
```

下載`etcd`相關檔案，我們將來管理 Etcd：
```sh
$ export ETCD_CONF_URL="https://kairen.github.io/files/manual-v1.8/master"
$ wget "${ETCD_CONF_URL}/etcd.conf" -O /etc/etcd/etcd.conf
$ wget "${ETCD_CONF_URL}/etcd.service" -O /lib/systemd/system/etcd.service
```
> 若與該教學 IP 不同的話，請用自己 IP 取代`172.16.35.12`。

建立 var 存放資訊，然後啟動 Etcd 服務:
```sh
$ mkdir -p /var/lib/etcd && chown etcd:etcd -R /var/lib/etcd /etc/etcd
$ systemctl enable etcd.service && systemctl start etcd.service
```

透過簡單指令驗證：
```sh
$ export CA="/etc/etcd/ssl"
$ ETCDCTL_API=3 etcdctl \
    --cacert=${CA}/etcd-ca.pem \
    --cert=${CA}/etcd.pem \
    --key=${CA}/etcd-key.pem \
    --endpoints="https://172.16.35.12:2379" \
    endpoint health
# output
https://172.16.35.12:2379 is healthy: successfully committed proposal: took = 641.36µs
```

## Kubernetes Master
Master 是 Kubernetes 的大總管，主要建置`apiserver`、`Controller manager`與`Scheduler`來元件管理所有 Node。本步驟將下載 Kubernetes 並安裝至 `master1`上，然後產生相關 TLS Cert 與 CA 金鑰，提供給叢集元件認證使用。

### 下載 Kubernetes 元件
首先透過網路取得所有需要的執行檔案：
```sh
# Download Kubernetes
$ export KUBE_URL="https://storage.googleapis.com/kubernetes-release/release/v1.8.2/bin/linux/amd64"
$ wget "${KUBE_URL}/kubelet" -O /usr/local/bin/kubelet
$ wget "${KUBE_URL}/kubectl" -O /usr/local/bin/kubectl
$ chmod +x /usr/local/bin/kubelet /usr/local/bin/kubectl

# Download CNI
$ mkdir -p /opt/cni/bin && cd /opt/cni/bin
$ export CNI_URL="https://github.com/containernetworking/plugins/releases/download"
$ wget -qO- --show-progress "${CNI_URL}/v0.6.0/cni-plugins-amd64-v0.6.0.tgz" | tar -zx
```

### 建立叢集 CA 與 Certificates
在這部分，將會需要產生 client 與 server 的各元件 certificates，並且替 Kubernetes admin user 產生 client 證書。

建立`pki`資料夾，然後進入目錄完成以下操作。
```sh
$ mkdir -p /etc/kubernetes/pki && cd /etc/kubernetes/pki
$ export PKI_URL="https://kairen.github.io/files/manual-v1.8/pki"
$ export KUBE_APISERVER="https://172.16.35.12:6443"
```

下載`ca-config.json`與`ca-csr.json`檔案，並產生 CA 金鑰：
```sh
$ wget "${PKI_URL}/ca-config.json" "${PKI_URL}/ca-csr.json"
$ cfssl gencert -initca ca-csr.json | cfssljson -bare ca
$ ls ca*.pem
ca-key.pem  ca.pem
```

#### API server certificate
下載`apiserver-csr.json`檔案，並產生 kube-apiserver certificate 證書：
```sh
$ wget "${PKI_URL}/apiserver-csr.json"
$ cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname=10.96.0.1,172.16.35.12,127.0.0.1,kubernetes.default \
  -profile=kubernetes \
  apiserver-csr.json | cfssljson -bare apiserver

$ ls apiserver*.pem
apiserver-key.pem  apiserver.pem
```
> 若節點 IP 不同，需要修改`apiserver-csr.json`的`hosts`。

#### Front proxy certificate
下載`front-proxy-ca-csr.json`檔案，並產生 Front proxy CA 金鑰，Front proxy 主要是用在 API aggregator 上:
```sh
$ wget "${PKI_URL}/front-proxy-ca-csr.json"
$ cfssl gencert \
  -initca front-proxy-ca-csr.json | cfssljson -bare front-proxy-ca

$ ls front-proxy-ca*.pem
front-proxy-ca-key.pem  front-proxy-ca.pem
```

下載`front-proxy-client-csr.json`檔案，並產生 front-proxy-client 證書：
```sh
$ wget "${PKI_URL}/front-proxy-client-csr.json"
$ cfssl gencert \
  -ca=front-proxy-ca.pem \
  -ca-key=front-proxy-ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  front-proxy-client-csr.json | cfssljson -bare front-proxy-client

$ ls front-proxy-client*.pem
front-proxy-client-key.pem  front-proxy-client.pem
```

#### Bootstrap Token
由於透過手動建立 CA 方式太過繁雜，只適合少量機器，因為每次簽證時都需要綁定 Node IP，隨機器增加會帶來很多困擾，因此這邊使用 TLS Bootstrapping 方式進行授權，由 apiserver 自動給符合條件的 Node 發送證書來授權加入叢集。

主要做法是 kubelet 啟動時，向 kube-apiserver 傳送 TLS Bootstrapping 請求，而 kube-apiserver 驗證 kubelet 請求的 token 是否與設定的一樣，若一樣就自動產生 kubelet 證書與金鑰。具體作法可以參考 [TLS bootstrapping](https://kubernetes.io/docs/admin/kubelet-tls-bootstrapping/)。

首先建立一個變數來產生`BOOTSTRAP_TOKEN`，並建立 `bootstrap.conf` 的 kubeconfig 檔：
```sh
$ export BOOTSTRAP_TOKEN=$(head -c 16 /dev/urandom | od -An -t x | tr -d ' ')
$ cat <<EOF > /etc/kubernetes/token.csv
${BOOTSTRAP_TOKEN},kubelet-bootstrap,10001,"system:kubelet-bootstrap"
EOF

# bootstrap set-cluster
$ kubectl config set-cluster kubernetes \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=${KUBE_APISERVER} \
    --kubeconfig=../bootstrap.conf

# bootstrap set-credentials
$ kubectl config set-credentials kubelet-bootstrap \
    --token=${BOOTSTRAP_TOKEN} \
    --kubeconfig=../bootstrap.conf

# bootstrap set-context
$ kubectl config set-context default \
    --cluster=kubernetes \
    --user=kubelet-bootstrap \
   --kubeconfig=../bootstrap.conf

# bootstrap set default context
$ kubectl config use-context default --kubeconfig=../bootstrap.conf
```
> 若想要用 CA 方式來認證，可以參考 [Kubelet certificate](https://gist.github.com/kairen/60ad8545b79e8e7aa9bdc8a2893df7a0)。

#### Admin certificate
下載`admin-csr.json`檔案，並產生 admin certificate 證書：
```sh
$ wget "${PKI_URL}/admin-csr.json"
$ cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  admin-csr.json | cfssljson -bare admin

$ ls admin*.pem
admin-key.pem  admin.pem
```

接著透過以下指令產生名稱為 `admin.conf` 的 kubeconfig 檔：
```sh
# admin set-cluster
$ kubectl config set-cluster kubernetes \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=${KUBE_APISERVER} \
    --kubeconfig=../admin.conf

# admin set-credentials
$ kubectl config set-credentials kubernetes-admin \
    --client-certificate=admin.pem \
    --client-key=admin-key.pem \
    --embed-certs=true \
    --kubeconfig=../admin.conf

# admin set-context
$ kubectl config set-context kubernetes-admin@kubernetes \
    --cluster=kubernetes \
    --user=kubernetes-admin \
    --kubeconfig=../admin.conf

# admin set default context
$ kubectl config use-context kubernetes-admin@kubernetes \
    --kubeconfig=../admin.conf
```

#### Controller manager certificate
下載`manager-csr.json`檔案，並產生 kube-controller-manager certificate 證書：
```sh
$ wget "${PKI_URL}/manager-csr.json"
$ cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  manager-csr.json | cfssljson -bare controller-manager

$ ls controller-manager*.pem
```
> 若節點 IP 不同，需要修改`manager-csr.json`的`hosts`。

接著透過以下指令產生名稱為`controller-manager.conf`的 kubeconfig 檔：
```sh
# controller-manager set-cluster
$ kubectl config set-cluster kubernetes \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=${KUBE_APISERVER} \
    --kubeconfig=../controller-manager.conf

# controller-manager set-credentials
$ kubectl config set-credentials system:kube-controller-manager \
    --client-certificate=controller-manager.pem \
    --client-key=controller-manager-key.pem \
    --embed-certs=true \
    --kubeconfig=../controller-manager.conf

# controller-manager set-context
$ kubectl config set-context system:kube-controller-manager@kubernetes \
    --cluster=kubernetes \
    --user=system:kube-controller-manager \
    --kubeconfig=../controller-manager.conf

# controller-manager set default context
$ kubectl config use-context system:kube-controller-manager@kubernetes \
    --kubeconfig=../controller-manager.conf
```

#### Scheduler certificate
下載`scheduler-csr.json`檔案，並產生 kube-scheduler certificate 證書：
```sh
$ wget "${PKI_URL}/scheduler-csr.json"
$ cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  scheduler-csr.json | cfssljson -bare scheduler

$ ls scheduler*.pem
scheduler-key.pem  scheduler.pem
```
> 若節點 IP 不同，需要修改`scheduler-csr.json`的`hosts`。

接著透過以下指令產生名稱為 `scheduler.conf` 的 kubeconfig 檔：
```sh
# scheduler set-cluster
$ kubectl config set-cluster kubernetes \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=${KUBE_APISERVER} \
    --kubeconfig=../scheduler.conf

# scheduler set-credentials
$ kubectl config set-credentials system:kube-scheduler \
    --client-certificate=scheduler.pem \
    --client-key=scheduler-key.pem \
    --embed-certs=true \
    --kubeconfig=../scheduler.conf

# scheduler set-context
$ kubectl config set-context system:kube-scheduler@kubernetes \
    --cluster=kubernetes \
    --user=system:kube-scheduler \
    --kubeconfig=../scheduler.conf

# scheduler set default context
$ kubectl config use-context system:kube-scheduler@kubernetes \
    --kubeconfig=../scheduler.conf
```

#### Kubelet master certificate
下載`kubelet-csr.json`檔案，並產生 master node certificate 證書：
```sh
$ wget "${PKI_URL}/kubelet-csr.json"
$ sed -i 's/$NODE/master1/g' kubelet-csr.json
$ cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname=master1,172.16.35.12 \
  -profile=kubernetes \
  kubelet-csr.json | cfssljson -bare kubelet

$ ls kubelet*.pem
kubelet-key.pem  kubelet.pem
```
> 這邊`$NODE`需要隨節點名稱不同而改變。

接著透過以下指令產生名稱為 `kubelet.conf` 的 kubeconfig 檔：
```sh
# kubelet set-cluster
$ kubectl config set-cluster kubernetes \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=${KUBE_APISERVER} \
    --kubeconfig=../kubelet.conf

# kubelet set-credentials
$ kubectl config set-credentials system:node:master1 \
    --client-certificate=kubelet.pem \
    --client-key=kubelet-key.pem \
    --embed-certs=true \
    --kubeconfig=../kubelet.conf

# kubelet set-context
$ kubectl config set-context system:node:master1@kubernetes \
    --cluster=kubernetes \
    --user=system:node:master1 \
    --kubeconfig=../kubelet.conf

# kubelet set default context
$ kubectl config use-context system:node:master1@kubernetes \
    --kubeconfig=../kubelet.conf
```

#### Service account key
Service account 不是透過 CA 進行認證，因此不要透過 CA 來做 Service account key 的檢查，這邊建立一組 Private 與 Public 金鑰提供給 Service account key 使用：
```sh
$ openssl genrsa -out sa.key 2048
$ openssl rsa -in sa.key -pubout -out sa.pub
$ ls sa.*
sa.key  sa.pub
```

完成後刪除不必要檔案：
```sh
$ rm -rf *.json *.csr
```

確認`/etc/kubernetes`與`/etc/kubernetes/pki`有以下檔案：
```sh
$ ls /etc/kubernetes/
admin.conf  bootstrap.conf  controller-manager.conf  kubelet.conf  pki  scheduler.conf  token.csv

$ ls /etc/kubernetes/pki
admin-key.pem  apiserver-key.pem  ca-key.pem  controller-manager-key.pem  front-proxy-ca-key.pem  front-proxy-client-key.pem  kubelet-key.pem  sa.key  scheduler-key.pem
admin.pem      apiserver.pem      ca.pem      controller-manager.pem      front-proxy-ca.pem      front-proxy-client.pem      kubelet.pem      sa.pub  scheduler.pem
```

### 安裝 Kubernetes 核心元件
首先下載 Kubernetes 核心元件 YAML 檔案，這邊我們不透過 Binary 方案來建立 Master 核心元件，而是利用 Kubernetes Static Pod 來達成，因此需下載所有核心元件的`Static Pod`檔案到`/etc/kubernetes/manifests`目錄：
```sh
$ export CORE_URL="https://kairen.github.io/files/manual-v1.8/master"
$ mkdir -p /etc/kubernetes/manifests && cd /etc/kubernetes/manifests
$ for FILE in apiserver manager scheduler; do
    wget "${CORE_URL}/${FILE}.yml.conf" -O ${FILE}.yml
  done
```
> 若`IP`與教學設定不同的話，請記得修改`apiserver.yml`、`manager.yml`、`scheduler.yml`。
> apiserver 中的 `NodeRestriction` 請參考 [Using Node Authorization](https://kubernetes.io/docs/admin/authorization/node/)。

產生一個用來加密 Etcd 的 Key：
```sh
$ head -c 32 /dev/urandom | base64
SUpbL4juUYyvxj3/gonV5xVEx8j769/99TSAf8YT/sQ=
```

在`/etc/kubernetes/`目錄下，建立`encryption.yml`的加密 YAML 檔案：
```sh
$ cat <<EOF > /etc/kubernetes/encryption.yml
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: SUpbL4juUYyvxj3/gonV5xVEx8j769/99TSAf8YT/sQ=
      - identity: {}
EOF
```
> Etcd 資料加密可參考這篇 [Encrypting data at rest](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/)。

在`/etc/kubernetes/`目錄下，建立`audit-policy.yml`的進階稽核策略 YAML 檔：
```sh
$ cat <<EOF > /etc/kubernetes/audit-policy.yml
apiVersion: audit.k8s.io/v1beta1
kind: Policy
rules:
- level: Metadata
EOF
```
> Audit Policy 請參考這篇 [Auditing](https://kubernetes.io/docs/tasks/debug-application-cluster/audit/)。

下載`kubelet.service`相關檔案來管理 kubelet：
```sh
$ export KUBELET_URL="https://kairen.github.io/files/manual-v1.8/master"
$ mkdir -p /etc/systemd/system/kubelet.service.d
$ wget "${KUBELET_URL}/kubelet.service" -O /lib/systemd/system/kubelet.service
$ wget "${KUBELET_URL}/10-kubelet.conf" -O /etc/systemd/system/kubelet.service.d/10-kubelet.conf
```

最後建立 var 存放資訊，然後啟動 kubelet 服務:
```sh
$ mkdir -p /var/lib/kubelet /var/log/kubernetes
$ systemctl enable kubelet.service && systemctl start kubelet.service
```

完成後會需要一段時間來下載映像檔與啟動元件，可以利用該指令來監看：
```sh
$ watch netstat -ntlp
tcp        0      0 127.0.0.1:10248         0.0.0.0:*               LISTEN      23012/kubelet
tcp        0      0 127.0.0.1:10251         0.0.0.0:*               LISTEN      22305/kube-schedule
tcp        0      0 127.0.0.1:10252         0.0.0.0:*               LISTEN      22529/kube-controll
tcp6       0      0 :::6443                 :::*                    LISTEN      22956/kube-apiserve
```
> 若看到以上資訊表示服務正常啟動，若發生問題可以用`docker cli`來查看。

完成後，複製 admin kubeconfig 檔案，並透過簡單指令驗證：
```sh
$ cp /etc/kubernetes/admin.conf ~/.kube/config
$ kubectl get cs
NAME                 STATUS    MESSAGE              ERROR
etcd-0               Healthy   {"health": "true"}
scheduler            Healthy   ok
controller-manager   Healthy   ok

$ kubectl get node
NAME      STATUS     ROLES     AGE       VERSION
master1   NotReady   master    4m        v1.8.2

$ kubectl -n kube-system get po
NAME                              READY     STATUS    RESTARTS   AGE
kube-apiserver-master1            1/1       Running   0          4m
kube-controller-manager-master1   1/1       Running   0          4m
kube-scheduler-master1            1/1       Running   0          4m
```

確認服務能夠執行 logs 等指令：
```sh
$ kubectl -n kube-system logs -f kube-scheduler-master1
Error from server (Forbidden): Forbidden (user=kube-apiserver, verb=get, resource=nodes, subresource=proxy) ( pods/log kube-apiserver-master1)
```
> 這邊會發現出現 403 Forbidden 問題，這是因為 `kube-apiserver` user 並沒有 nodes 的資源權限，屬於正常。

由於上述權限問題，我們必需建立一個 `apiserver-to-kubelet-rbac.yml` 來定義權限，以供我們執行 logs、exec 等指令：
```sh
$ cd /etc/kubernetes/
$ export URL="https://kairen.github.io/files/manual-v1.8/master"
$ wget "${URL}/apiserver-to-kubelet-rbac.yml.conf" -O apiserver-to-kubelet-rbac.yml
$ kubectl apply -f apiserver-to-kubelet-rbac.yml

# 測試 logs
$ kubectl -n kube-system logs -f kube-scheduler-master1
...
I1031 03:22:42.527697       1 leaderelection.go:184] successfully acquired lease kube-system/kube-scheduler
```

## Kubernetes Node
Node 是主要執行容器實例的節點，可視為工作節點。在這步驟我們會下載 Kubernetes binary 檔，並建立 node 的 certificate 來提供給節點註冊認證用。Kubernetes 使用`Node Authorizer`來提供[Authorization mode](https://kubernetes.io/docs/admin/authorization/node/)，這種授權模式會替 Kubelet 生成 API request。

在開始前，我們先在`master1`將需要的 ca 與 cert 複製到 Node 節點上：
```sh
$ for NODE in node1 node2; do
    ssh ${NODE} "mkdir -p /etc/kubernetes/pki/"
    ssh ${NODE} "mkdir -p /etc/etcd/ssl"
    # Etcd ca and cert
    for FILE in etcd-ca.pem etcd.pem etcd-key.pem; do
      scp /etc/etcd/ssl/${FILE} ${NODE}:/etc/etcd/ssl/${FILE}
    done
    # Kubernetes ca and cert
    for FILE in pki/ca.pem pki/ca-key.pem bootstrap.conf; do
      scp /etc/kubernetes/${FILE} ${NODE}:/etc/kubernetes/${FILE}
    done
  done
```

### 下載 Kubernetes 元件
首先透過網路取得所有需要的執行檔案：
```sh
# Download Kubernetes
$ export KUBE_URL="https://storage.googleapis.com/kubernetes-release/release/v1.8.2/bin/linux/amd64"
$ wget "${KUBE_URL}/kubelet" -O /usr/local/bin/kubelet
$ chmod +x /usr/local/bin/kubelet

# Download CNI
$ mkdir -p /opt/cni/bin && cd /opt/cni/bin
$ export CNI_URL="https://github.com/containernetworking/plugins/releases/download"
$ wget -qO- --show-progress "${CNI_URL}/v0.6.0/cni-plugins-amd64-v0.6.0.tgz" | tar -zx
```

### 設定 Kubernetes node
接著下載 Kubernetes 相關檔案，包含 drop-in file、systemd service 檔案等：
```sh
$ export KUBELET_URL="https://kairen.github.io/files/manual-v1.8/node"
$ mkdir -p /etc/systemd/system/kubelet.service.d
$ wget "${KUBELET_URL}/kubelet.service" -O /lib/systemd/system/kubelet.service
$ wget "${KUBELET_URL}/10-kubelet.conf" -O /etc/systemd/system/kubelet.service.d/10-kubelet.conf
```

接著在所有`node`建立 var 存放資訊，然後啟動 kubelet 服務:
```sh
$ mkdir -p /var/lib/kubelet /var/log/kubernetes /etc/kubernetes/manifests
$ systemctl enable kubelet.service && systemctl start kubelet.service
```
> P.S. 重複一樣動作來完成其他節點。

### 授權 Kubernetes Node
當所有節點都完成後，在`master`節點，因為我們採用 TLS Bootstrapping，所需要建立一個 ClusterRoleBinding：
```sh
$ kubectl create clusterrolebinding kubelet-bootstrap \
    --clusterrole=system:node-bootstrapper \
    --user=kubelet-bootstrap
```

在`master`透過簡單指令驗證，會看到節點處於`pending`：
```sh
$ kubectl get csr
NAME                                                   AGE       REQUESTOR           CONDITION
node-csr-YWf97ZrLCTlr2hmXsNLfjVLwaLfZRsu52FRKOYjpcBE   2s        kubelet-bootstrap   Pending
node-csr-eq4q6ffOwT4yqYQNU6sT7mphPOQdFN6yulMVZeu6pkE   2s        kubelet-bootstrap   Pending
```

透過 kubectl 來允許節點加入叢集：
```sh
$ kubectl get csr | awk '/Pending/ {print $1}' | xargs kubectl certificate approve
certificatesigningrequest "node-csr-YWf97ZrLCTlr2hmXsNLfjVLwaLfZRsu52FRKOYjpcBE" approved
certificatesigningrequest "node-csr-eq4q6ffOwT4yqYQNU6sT7mphPOQdFN6yulMVZeu6pkE" approved

$ kubectl get csr
NAME                                                   AGE       REQUESTOR           CONDITION
node-csr-YWf97ZrLCTlr2hmXsNLfjVLwaLfZRsu52FRKOYjpcBE   30s       kubelet-bootstrap   Approved,Issued
node-csr-eq4q6ffOwT4yqYQNU6sT7mphPOQdFN6yulMVZeu6pkE   30s       kubelet-bootstrap   Approved,Issued

$ kubectl get no
NAME      STATUS     ROLES     AGE       VERSION
master1   NotReady   master    15m       v1.8.2
node1     NotReady   <none>    8m        v1.8.2
node2     NotReady   <none>    6s        v1.8.2
```

## Kubernetes Core Addons 部署
當完成上面所有步驟後，接著我們需要安裝一些插件，而這些有部分是非常重要跟好用的，如`Kube-dns`與`Kube-proxy`等。

### Kube-proxy addon
[Kube-proxy](https://github.com/kubernetes/kubernetes/tree/master/cluster/addons/kube-proxy) 是實現 Service 的關鍵元件，kube-proxy 會在每台節點上執行，然後監聽 API Server 的 Service 與 Endpoint 資源物件的改變，然後來依據變化執行 iptables 來實現網路的轉發。這邊我們會需要建議一個 DaemonSet 來執行，並且建立一些需要的 certificate。

首先在`master1`下載`kube-proxy-csr.json`檔案，並產生 kube-proxy certificate 證書：
```sh
$ export PKI_URL="https://kairen.github.io/files/manual-v1.8/pki"
$ cd /etc/kubernetes/pki
$ wget "${PKI_URL}/kube-proxy-csr.json" "${PKI_URL}/ca-config.json"
$ cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  kube-proxy-csr.json | cfssljson -bare kube-proxy

$ ls kube-proxy*.pem
kube-proxy-key.pem  kube-proxy.pem
```

接著透過以下指令產生名稱為 `kube-proxy.conf` 的 kubeconfig 檔：
```sh
# kube-proxy set-cluster
$ kubectl config set-cluster kubernetes \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server="https://172.16.35.12:6443" \
    --kubeconfig=../kube-proxy.conf

# kube-proxy set-credentials
$ kubectl config set-credentials system:kube-proxy \
    --client-key=kube-proxy-key.pem \
    --client-certificate=kube-proxy.pem \
    --embed-certs=true \
    --kubeconfig=../kube-proxy.conf

# kube-proxy set-context
$ kubectl config set-context system:kube-proxy@kubernetes \
    --cluster=kubernetes \
    --user=system:kube-proxy \
    --kubeconfig=../kube-proxy.conf

# kube-proxy set default context
$ kubectl config use-context system:kube-proxy@kubernetes \
    --kubeconfig=../kube-proxy.conf
```

完成後刪除不必要檔案：
```sh
$ rm -rf *.json
```

確認`/etc/kubernetes`有以下檔案：
```sh
$ ls /etc/kubernetes/
admin.conf        bootstrap.conf           encryption.yml  kube-proxy.conf  pki             token.csv
audit-policy.yml  controller-manager.conf  kubelet.conf    manifests        scheduler.conf
```

在`master1`將`kube-proxy`相關檔案複製到 Node 節點上：
```sh
$ for NODE in node1 node2; do
    for FILE in pki/kube-proxy.pem pki/kube-proxy-key.pem kube-proxy.conf; do
      scp /etc/kubernetes/${FILE} ${NODE}:/etc/kubernetes/${FILE}
    done
  done
```

完成後，在`master1`透過 kubectl 來建立 kube-proxy daemon：
```sh
$ export ADDON_URL="https://kairen.github.io/files/manual-v1.8/addon"
$ mkdir -p /etc/kubernetes/addons && cd /etc/kubernetes/addons
$ wget "${ADDON_URL}/kube-proxy.yml.conf" -O kube-proxy.yml
$ kubectl apply -f kube-proxy.yml
$ kubectl -n kube-system get po -l k8s-app=kube-proxy
NAME               READY     STATUS    RESTARTS   AGE
kube-proxy-bpp7q   1/1       Running   0          47s
kube-proxy-cztvh   1/1       Running   0          47s
kube-proxy-q7mm4   1/1       Running   0          47s
```

### Kube-dns addon
[Kube DNS](https://github.com/kubernetes/kubernetes/tree/master/cluster/addons/dns) 是 Kubernetes 叢集內部 Pod 之間互相溝通的重要 Addon，它允許 Pod 可以透過 Domain Name 方式來連接 Service，其主要由 Kube DNS 與 Sky DNS 組合而成，透過 Kube DNS 監聽 Service 與 Endpoint 變化，來提供給 Sky DNS 資訊，已更新解析位址。

安裝只需要在`master1`透過 kubectl 來建立 kube-dns deployment 即可：
```sh
$ export ADDON_URL="https://kairen.github.io/files/manual-v1.8/addon"
$ wget "${ADDON_URL}/kube-dns.yml.conf" -O kube-dns.yml
$ kubectl apply -f kube-dns.yml
$ kubectl -n kube-system get po -l k8s-app=kube-dns
NAME                        READY     STATUS    RESTARTS   AGE
kube-dns-6cb549f55f-h4zr5   0/3       Pending   0          40s
```

## Calico Network 安裝與設定
Calico 是一款純 Layer 3 的資料中心網路方案(不需要 Overlay 網路)，Calico 好處是他已與各種雲原生平台有良好的整合，而 Calico 在每一個節點利用 Linux Kernel 實現高效的 vRouter 來負責資料的轉發，而當資料中心複雜度增加時，可以用 BGP route reflector 來達成。

首先在`master1`透過 kubectl 建立 Calico policy controller：
```sh
$ export CALICO_CONF_URL="https://kairen.github.io/files/manual-v1.8/network"
$ wget "${CALICO_CONF_URL}/calico-controller.yml.conf" -O calico-controller.yml
$ kubectl apply -f calico-controller.yml
$ kubectl -n kube-system get po -l k8s-app=calico-policy
NAME                                        READY     STATUS    RESTARTS   AGE
calico-policy-controller-5ff8b4549d-tctmm   0/1       Pending   0          5s
```

在`master1`下載 Calico CLI 工具：
```sh
$ wget https://github.com/projectcalico/calicoctl/releases/download/v1.6.1/calicoctl
$ chmod +x calicoctl && mv calicoctl /usr/local/bin/
```

然後在`所有`節點下載 Calico，並執行以下步驟：
```sh
$ export CALICO_URL="https://github.com/projectcalico/cni-plugin/releases/download/v1.11.0"
$ wget -N -P /opt/cni/bin ${CALICO_URL}/calico
$ wget -N -P /opt/cni/bin ${CALICO_URL}/calico-ipam
$ chmod +x /opt/cni/bin/calico /opt/cni/bin/calico-ipam
```

接著在`所有`節點下載 CNI plugins設定檔，以及 calico-node.service：
```sh
$ mkdir -p /etc/cni/net.d
$ export CALICO_CONF_URL="https://kairen.github.io/files/manual-v1.8/network"
$ wget "${CALICO_CONF_URL}/10-calico.conf" -O /etc/cni/net.d/10-calico.conf
$ wget "${CALICO_CONF_URL}/calico-node.service" -O /lib/systemd/system/calico-node.service
```
> 若部署的機器是使用虛擬機，如 Virtualbox 等的話，請修改`calico-node.service`檔案，並在`IP_AUTODETECTION_METHOD`(包含 IP6)部分指定綁定的網卡，以避免預設綁定到 NAT 網路上。

之後在`所有`節點啟動 Calico-node:
```sh
$ systemctl enable calico-node.service && systemctl start calico-node.service
```

在`master1`查看 Calico nodes:
```sh
$ cat <<EOF > ~/calico-rc
export ETCD_ENDPOINTS="https://172.16.35.12:2379"
export ETCD_CA_CERT_FILE="/etc/etcd/ssl/etcd-ca.pem"
export ETCD_CERT_FILE="/etc/etcd/ssl/etcd.pem"
export ETCD_KEY_FILE="/etc/etcd/ssl/etcd-key.pem"
EOF

$ . ~/calico-rc
$ calicoctl get node -o wide
NAME      ASN       IPV4              IPV6
master1   (64512)   172.16.35.12/24
node1     (64512)   172.16.35.10/24
node2     (64512)   172.16.35.11/24
```

查看 pending 的 pod 是否已執行：
```sh
$ kubectl -n kube-system get po
NAME                                        READY     STATUS    RESTARTS   AGE
calico-policy-controller-5ff8b4549d-tctmm   1/1       Running   0          4m
kube-apiserver-master1                      1/1       Running   0          20m
kube-controller-manager-master1             1/1       Running   0          20m
kube-dns-6cb549f55f-h4zr5                   3/3       Running   0          5m
kube-proxy-fnrkb                            1/1       Running   0          6m
kube-proxy-l72bq                            1/1       Running   0          6m
kube-proxy-m6rfw                            1/1       Running   0          6m
kube-scheduler-master1                      1/1       Running   0          20m
```

最後若想省事，可以直接用 [Standard Hosted](https://docs.projectcalico.org/v2.6/getting-started/kubernetes/installation/hosted/hosted) 方式安裝。

## Kubernetes Extra Addons 部署
本節說明如何部署一些官方常用的 Addons，如 Dashboard、Heapster 等。

### Dashboard addon
[Dashboard](https://github.com/kubernetes/dashboard) 是 Kubernetes 社區官方開發的儀表板，有了儀表板後管理者就能夠透過 Web-based 方式來管理 Kubernetes 叢集，除了提升管理方便，也讓資源視覺化，讓人更直覺看見系統資訊的呈現結果。

首先我們要建立`kubernetes-dashboard-certs`，來提供給 Dashboard TLS 使用：
```sh
$ mkdir -p /etc/kubernetes/addons/certs && cd /etc/kubernetes/addons
$ openssl genrsa -des3 -passout pass:x -out certs/dashboard.pass.key 2048
$ openssl rsa -passin pass:x -in certs/dashboard.pass.key -out certs/dashboard.key
$ openssl req -new -key certs/dashboard.key -out certs/dashboard.csr -subj '/CN=kube-dashboard'
$ openssl x509 -req -sha256 -days 365 -in certs/dashboard.csr -signkey certs/dashboard.key -out certs/dashboard.crt
$ rm certs/dashboard.pass.key
$ kubectl create secret generic kubernetes-dashboard-certs\
    --from-file=certs -n kube-system
```

接著在`master1`透過 kubectl 來建立 kubernetes dashboard 即可：
```sh
$ export ADDON_URL="https://kairen.github.io/files/manual-v1.8/addon"
$ wget ${ADDON_URL}/kube-dashboard.yml.conf -O kube-dashboard.yml
$ kubectl apply -f kube-dashboard.yml
$ kubectl -n kube-system get po,svc -l k8s-app=kubernetes-dashboard
NAME                                      READY     STATUS    RESTARTS   AGE
po/kubernetes-dashboard-747c4f7cf-md5m8   1/1       Running   0          56s

NAME                       TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
svc/kubernetes-dashboard   ClusterIP   10.98.120.209   <none>        443/TCP   56s
```
> P.S. 這邊會額外建立一個名稱為`anonymous-open-door` Cluster Role Binding，這僅作為方便測試時使用，在一般情況下不要開啟，不然就會直接被存取所有 API。

完成後，就可以透過瀏覽器存取 [Dashboard](https://172.16.35.12:6443/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/)。

### Heapster addon
[Heapster](https://github.com/kubernetes/heapster) 是 Kubernetes 社區維護的容器叢集監控與效能分析工具。Heapster 會從 Kubernetes apiserver 取得所有 Node 資訊，然後再透過這些 Node 來取得 kubelet 上的資料，最後再將所有收集到資料送到 Heapster 的後台儲存 InfluxDB，最後利用 Grafana 來抓取 InfluxDB 的資料源來進行視覺化。

在`master1`透過 kubectl 來建立 kubernetes monitor  即可：
```sh
$ export ADDON_URL="https://kairen.github.io/files/manual-v1.8/addon"
$ wget ${ADDON_URL}/kube-monitor.yml.conf -O kube-monitor.yml
$ kubectl apply -f kube-monitor.yml
$ kubectl -n kube-system get po,svc
NAME                                           READY     STATUS    RESTARTS   AGE
...
po/heapster-74fb5c8cdc-62xzc                   4/4       Running   0          7m
po/influxdb-grafana-55bd7df44-nw4nc            2/2       Running   0          7m

NAME                       TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)             AGE
...
svc/heapster               ClusterIP   10.100.242.225   <none>        80/TCP              7m
svc/monitoring-grafana     ClusterIP   10.101.106.180   <none>        80/TCP              7m
svc/monitoring-influxdb    ClusterIP   10.109.245.142   <none>        8083/TCP,8086/TCP   7m
···
```

完成後，就可以透過瀏覽器存取 [Grafana Dashboard](https://172.16.35.12:6443/api/v1/proxy/namespaces/kube-system/services/monitoring-grafana)。

## 簡單部署 Nginx 服務
Kubernetes 可以選擇使用指令直接建立應用程式與服務，或者撰寫 YAML 與 JSON 檔案來描述部署應用程式的配置，以下將建立一個簡單的 Nginx 服務：
```sh
$ kubectl run nginx --image=nginx --port=80
$ kubectl expose deploy nginx --port=80 --type=LoadBalancer --external-ip=172.16.35.12
$ kubectl get svc,po
NAME             TYPE           CLUSTER-IP      EXTERNAL-IP    PORT(S)        AGE
svc/kubernetes   ClusterIP      10.96.0.1       <none>         443/TCP        1h
svc/nginx        LoadBalancer   10.97.121.243   172.16.35.12   80:30344/TCP   22s

NAME                        READY     STATUS    RESTARTS   AGE
po/nginx-7cbc4b4d9c-7796l   1/1       Running   0          28s       192.160.57.181   ,172.16.35.12   80:32054/TCP   21s
```
> 這邊`type`可以選擇 NodePort 與 LoadBalancer，在本地裸機部署，兩者差異在於`NodePort`只映射 Host port 到 Container port，而`LoadBalancer`則繼承`NodePort`額外多出映射 Host target port 到 Container port。

確認沒問題後即可在瀏覽器存取 http://172.16.35.12。

### 擴展服務數量
若叢集`node`節點增加了，而想讓 Nginx 服務提供可靠性的話，可以透過以下方式來擴展服務的副本：
```sh
$ kubectl scale deploy nginx --replicas=2

$ kubectl get pods -o wide
NAME                    READY     STATUS    RESTARTS   AGE       IP             NODE
nginx-158599303-0h9lr   1/1       Running   0          25s       10.244.100.5   node2
nginx-158599303-k7cbt   1/1       Running   0          1m        10.244.24.3    node1
```
