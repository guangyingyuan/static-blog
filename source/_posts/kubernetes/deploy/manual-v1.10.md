---
title: Kubernetes v1.10.x HA 全手動苦工安裝教學(TL;DR)
date: 2018-04-05 17:08:54
catalog: true
categories:
- Kubernetes
tags:
- Kubernetes
- Docker
- Calico
---
本篇延續過往`手動安裝方式`來部署 Kubernetes v1.10.x 版本的 High Availability 叢集，主要目的是學習 Kubernetes 安裝的一些元件關析與流程。若不想這麼累的話，可以參考 [Picking the Right Solution](https://kubernetes.io/docs/getting-started-guides/) 來選擇自己最喜歡的方式。

本次安裝的軟體版本：
* Kubernetes v1.10.0
* CNI v0.6.0
* Etcd v3.1.13
* Calico v3.0.4
* Docker CE latest version

<!--more-->

![](/images/kube/kubernetes-aa-ha.png)

## 節點資訊
本教學將以下列節點數與規格來進行部署 Kubernetes 叢集，作業系統可採用`Ubuntu 16.x`與`CentOS 7.x`：

| IP Address | Hostname | CPU | Memory |
|------------|----------|-----|--------|
|192.16.35.11| k8s-m1   | 1   | 4G     |
|192.16.35.12| k8s-m2   | 1   | 4G     |
|192.16.35.13| k8s-m3   | 1   | 4G     |
|192.16.35.14| k8s-n1   | 1   | 4G     |
|192.16.35.15| k8s-n2   | 1   | 4G     |
|192.16.35.16| k8s-n2   | 1   | 4G     |

另外由所有 master 節點提供一組 VIP `192.16.35.10`。

> * 這邊`m`為主要控制節點，`n`為應用程式工作節點。
> * 所有操作全部用`root`使用者進行(方便用)，以 SRE 來說不推薦。
> * 可以下載 [Vagrantfile](https://kairen.github.io/files/manual-v1.10/Vagrantfile) 來建立 Virtualbox 虛擬機叢集。不過需要注意機器資源是否足夠。

## 事前準備
開始安裝前需要確保以下條件已達成：
* `所有節點`彼此網路互通，並且`k8s-m1` SSH 登入其他節點為 passwdless。
* 所有防火牆與 SELinux 已關閉。如 CentOS：

```sh
$ systemctl stop firewalld && systemctl disable firewalld
$ setenforce 0
$ vim /etc/selinux/config
SELINUX=disabled
```

* `所有節點`需要設定`/etc/hosts`解析到所有叢集主機。

```
...
192.16.35.11 k8s-m1
192.16.35.12 k8s-m2
192.16.35.13 k8s-m3
192.16.35.14 k8s-n1
192.16.35.15 k8s-n2
192.16.35.16 k8s-n3
```

* `所有節點`需要安裝 Docker CE 版本的容器引擎：

```sh
$ curl -fsSL "https://get.docker.com/" | sh
```
> 不管是在 `Ubuntu` 或 `CentOS` 都只需要執行該指令就會自動安裝最新版 Docker。
> CentOS 安裝完成後，需要再執行以下指令：
```sh
$ systemctl enable docker && systemctl start docker
```

* `所有節點`需要設定`/etc/sysctl.d/k8s.conf`的系統參數。

```sh
$ cat <<EOF > /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

$ sysctl -p /etc/sysctl.d/k8s.conf
```

* Kubernetes v1.8+ 要求關閉系統 Swap，若不關閉則需要修改 kubelet 設定參數，在`所有節點`利用以下指令關閉：

```sh
$ swapoff -a && sysctl -w vm.swappiness=0
```
> 記得`/etc/fstab`也要註解掉`SWAP`掛載。

* 在`所有節點`下載 Kubernetes 二進制執行檔：

```sh
$ export KUBE_URL="https://storage.googleapis.com/kubernetes-release/release/v1.10.0/bin/linux/amd64"
$ wget "${KUBE_URL}/kubelet" -O /usr/local/bin/kubelet
$ chmod +x /usr/local/bin/kubelet

# node 請忽略下載 kubectl
$ wget "${KUBE_URL}/kubectl" -O /usr/local/bin/kubectl
$ chmod +x /usr/local/bin/kubectl
```

* 在`所有節點`下載 Kubernetes CNI 二進制檔案：

```sh
$ mkdir -p /opt/cni/bin && cd /opt/cni/bin
$ export CNI_URL="https://github.com/containernetworking/plugins/releases/download"
$ wget -qO- --show-progress "${CNI_URL}/v0.6.0/cni-plugins-amd64-v0.6.0.tgz" | tar -zx
```

* 在`k8s-m1`需要安裝`CFSSL`工具，這將會用來建立 TLS Certificates。

```sh
$ export CFSSL_URL="https://pkg.cfssl.org/R1.2"
$ wget "${CFSSL_URL}/cfssl_linux-amd64" -O /usr/local/bin/cfssl
$ wget "${CFSSL_URL}/cfssljson_linux-amd64" -O /usr/local/bin/cfssljson
$ chmod +x /usr/local/bin/cfssl /usr/local/bin/cfssljson
```

## 建立叢集 CA keys 與 Certificates
在這個部分，將需要產生多個元件的 Certificates，這包含 Etcd、Kubernetes 元件等，並且每個叢集都會有一個根數位憑證認證機構(Root Certificate Authority)被用在認證 API Server 與 Kubelet 端的憑證。

> P.S. 這邊要注意 CA JSON 檔的`CN(Common Name)`與`O(Organization)`等內容是會影響 Kubernetes 元件認證的。

### Etcd
首先在`k8s-m1`建立`/etc/etcd/ssl`資料夾，然後進入目錄完成以下操作。
```sh
$ mkdir -p /etc/etcd/ssl && cd /etc/etcd/ssl
$ export PKI_URL="https://kairen.github.io/files/manual-v1.10/pki"
```

下載`ca-config.json`與`etcd-ca-csr.json`檔案，並從 CSR json 產生 CA keys 與 Certificate：
```sh
$ wget "${PKI_URL}/ca-config.json" "${PKI_URL}/etcd-ca-csr.json"
$ cfssl gencert -initca etcd-ca-csr.json | cfssljson -bare etcd-ca
```

下載`etcd-csr.json`檔案，並產生 Etcd 證書：
```sh
$ wget "${PKI_URL}/etcd-csr.json"
$ cfssl gencert \
  -ca=etcd-ca.pem \
  -ca-key=etcd-ca-key.pem \
  -config=ca-config.json \
  -hostname=127.0.0.1,192.16.35.11,192.16.35.12,192.16.35.13 \
  -profile=kubernetes \
  etcd-csr.json | cfssljson -bare etcd
```
> `-hostname`需修改成所有 masters 節點。

完成後刪除不必要檔案：
```sh
$ rm -rf *.json *.csr
```

確認`/etc/etcd/ssl`有以下檔案：
```sh
$ ls /etc/etcd/ssl
etcd-ca-key.pem  etcd-ca.pem  etcd-key.pem  etcd.pem
```

複製相關檔案至其他 Etcd 節點，這邊為所有`master`節點：
```sh
$ for NODE in k8s-m2 k8s-m3; do
    echo "--- $NODE ---"
    ssh ${NODE} "mkdir -p /etc/etcd/ssl"
    for FILE in etcd-ca-key.pem  etcd-ca.pem  etcd-key.pem  etcd.pem; do
      scp /etc/etcd/ssl/${FILE} ${NODE}:/etc/etcd/ssl/${FILE}
    done
  done
```

### Kubernetes
在`k8s-m1`建立`pki`資料夾，然後進入目錄完成以下章節操作。
```sh
$ mkdir -p /etc/kubernetes/pki && cd /etc/kubernetes/pki
$ export PKI_URL="https://kairen.github.io/files/manual-v1.10/pki"
$ export KUBE_APISERVER="https://192.16.35.10:6443"
```

下載`ca-config.json`與`ca-csr.json`檔案，並產生 CA 金鑰：
```sh
$ wget "${PKI_URL}/ca-config.json" "${PKI_URL}/ca-csr.json"
$ cfssl gencert -initca ca-csr.json | cfssljson -bare ca
$ ls ca*.pem
ca-key.pem  ca.pem
```

#### API Server Certificate
下載`apiserver-csr.json`檔案，並產生 kube-apiserver 憑證：
```sh
$ wget "${PKI_URL}/apiserver-csr.json"
$ cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname=10.96.0.1,192.16.35.10,127.0.0.1,kubernetes.default \
  -profile=kubernetes \
  apiserver-csr.json | cfssljson -bare apiserver

$ ls apiserver*.pem
apiserver-key.pem  apiserver.pem
```
> * 這邊`-hostname`的`10.96.0.1`是 Cluster IP 的 Kubernetes 端點;
> * `192.16.35.10`為虛擬 IP 位址(VIP);
> * `kubernetes.default`為 Kubernetes DN。

#### Front Proxy Certificate
下載`front-proxy-ca-csr.json`檔案，並產生 Front Proxy CA 金鑰，Front Proxy 主要是用在 API aggregator 上:
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

#### Admin Certificate
下載`admin-csr.json`檔案，並產生 admin certificate 憑證：
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
# admin set cluster
$ kubectl config set-cluster kubernetes \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=${KUBE_APISERVER} \
    --kubeconfig=../admin.conf

# admin set credentials
$ kubectl config set-credentials kubernetes-admin \
    --client-certificate=admin.pem \
    --client-key=admin-key.pem \
    --embed-certs=true \
    --kubeconfig=../admin.conf

# admin set context
$ kubectl config set-context kubernetes-admin@kubernetes \
    --cluster=kubernetes \
    --user=kubernetes-admin \
    --kubeconfig=../admin.conf

# admin set default context
$ kubectl config use-context kubernetes-admin@kubernetes \
    --kubeconfig=../admin.conf
```

#### Controller Manager Certificate
下載`manager-csr.json`檔案，並產生 kube-controller-manager certificate 憑證：
```sh
$ wget "${PKI_URL}/manager-csr.json"
$ cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  manager-csr.json | cfssljson -bare controller-manager

$ ls controller-manager*.pem
controller-manager-key.pem  controller-manager.pem
```
> 若節點 IP 不同，需要修改`manager-csr.json`的`hosts`。

接著透過以下指令產生名稱為`controller-manager.conf`的 kubeconfig 檔：
```sh
# controller-manager set cluster
$ kubectl config set-cluster kubernetes \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=${KUBE_APISERVER} \
    --kubeconfig=../controller-manager.conf

# controller-manager set credentials
$ kubectl config set-credentials system:kube-controller-manager \
    --client-certificate=controller-manager.pem \
    --client-key=controller-manager-key.pem \
    --embed-certs=true \
    --kubeconfig=../controller-manager.conf

# controller-manager set context
$ kubectl config set-context system:kube-controller-manager@kubernetes \
    --cluster=kubernetes \
    --user=system:kube-controller-manager \
    --kubeconfig=../controller-manager.conf

# controller-manager set default context
$ kubectl config use-context system:kube-controller-manager@kubernetes \
    --kubeconfig=../controller-manager.conf
```

#### Scheduler Certificate
下載`scheduler-csr.json`檔案，並產生 kube-scheduler certificate 憑證：
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
# scheduler set cluster
$ kubectl config set-cluster kubernetes \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=${KUBE_APISERVER} \
    --kubeconfig=../scheduler.conf

# scheduler set credentials
$ kubectl config set-credentials system:kube-scheduler \
    --client-certificate=scheduler.pem \
    --client-key=scheduler-key.pem \
    --embed-certs=true \
    --kubeconfig=../scheduler.conf

# scheduler set context
$ kubectl config set-context system:kube-scheduler@kubernetes \
    --cluster=kubernetes \
    --user=system:kube-scheduler \
    --kubeconfig=../scheduler.conf

# scheduler use default context
$ kubectl config use-context system:kube-scheduler@kubernetes \
    --kubeconfig=../scheduler.conf
```

#### Master Kubelet Certificate
接著在`k8s-m1`節點下載`kubelet-csr.json`檔案，並產生所有`master`節點的憑證：
```sh
$ wget "${PKI_URL}/kubelet-csr.json"
$ for NODE in k8s-m1 k8s-m2 k8s-m3; do
    echo "--- $NODE ---"
    cp kubelet-csr.json kubelet-$NODE-csr.json;
    sed -i "s/\$NODE/$NODE/g" kubelet-$NODE-csr.json;
    cfssl gencert \
      -ca=ca.pem \
      -ca-key=ca-key.pem \
      -config=ca-config.json \
      -hostname=$NODE \
      -profile=kubernetes \
      kubelet-$NODE-csr.json | cfssljson -bare kubelet-$NODE
  done

$ ls kubelet*.pem
kubelet-k8s-m1-key.pem  kubelet-k8s-m1.pem  kubelet-k8s-m2-key.pem  kubelet-k8s-m2.pem  kubelet-k8s-m3-key.pem  kubelet-k8s-m3.pem
```
> 這邊需要依據節點修改`-hostname`與`$NODE`。

完成後複製 kubelet 憑證至其他`master`節點：
```sh
$ for NODE in k8s-m2 k8s-m3; do
    echo "--- $NODE ---"
    ssh ${NODE} "mkdir -p /etc/kubernetes/pki"
    for FILE in kubelet-$NODE-key.pem kubelet-$NODE.pem ca.pem; do
      scp /etc/kubernetes/pki/${FILE} ${NODE}:/etc/kubernetes/pki/${FILE}
    done
  done
```

接著執行以下指令產生名稱為`kubelet.conf`的 kubeconfig 檔：
```sh
$ for NODE in k8s-m1 k8s-m2 k8s-m3; do
    echo "--- $NODE ---"
    ssh ${NODE} "cd /etc/kubernetes/pki && \
      kubectl config set-cluster kubernetes \
        --certificate-authority=ca.pem \
        --embed-certs=true \
        --server=${KUBE_APISERVER} \
        --kubeconfig=../kubelet.conf && \
      kubectl config set-credentials system:node:${NODE} \
        --client-certificate=kubelet-${NODE}.pem \
        --client-key=kubelet-${NODE}-key.pem \
        --embed-certs=true \
        --kubeconfig=../kubelet.conf && \
      kubectl config set-context system:node:${NODE}@kubernetes \
        --cluster=kubernetes \
        --user=system:node:${NODE} \
        --kubeconfig=../kubelet.conf && \
      kubectl config use-context system:node:${NODE}@kubernetes \
        --kubeconfig=../kubelet.conf && \
      rm kubelet-${NODE}.pem kubelet-${NODE}-key.pem"
  done
```

#### Service Account Key
Service account 不是透過 CA 進行認證，因此不要透過 CA 來做 Service account key 的檢查，這邊建立一組 Private 與 Public 金鑰提供給 Service account key 使用：
```sh
$ openssl genrsa -out sa.key 2048
$ openssl rsa -in sa.key -pubout -out sa.pub
$ ls sa.*
sa.key  sa.pub
```

#### 刪除不必要檔案
所有資訊準備完成後，就可以將一些不必要檔案刪除：
```sh
$ rm -rf *.json *.csr scheduler*.pem controller-manager*.pem admin*.pem kubelet*.pem
```

#### 複製檔案至其他節點
複製憑證檔案至其他`master`節點：
```sh
$ for NODE in k8s-m2 k8s-m3; do
    echo "--- $NODE ---"
    for FILE in $(ls /etc/kubernetes/pki/); do
      scp /etc/kubernetes/pki/${FILE} ${NODE}:/etc/kubernetes/pki/${FILE}
    done
  done
```

複製 Kubernetes config 檔案至其他`master`節點：
```sh
$ for NODE in k8s-m2 k8s-m3; do
    echo "--- $NODE ---"
    for FILE in admin.conf controller-manager.conf scheduler.conf; do
      scp /etc/kubernetes/${FILE} ${NODE}:/etc/kubernetes/${FILE}
    done
  done
```

## Kubernetes Masters
本部分將說明如何建立與設定 Kubernetes Master 角色，過程中會部署以下元件：
* **kube-apiserver**：提供 REST APIs，包含授權、認證與狀態儲存等。
* **kube-controller-manager**：負責維護叢集的狀態，如自動擴展，滾動更新等。
* **kube-scheduler**：負責資源排程，依據預定的排程策略將 Pod 分配到對應節點上。
* **Etcd**：儲存叢集所有狀態的 Key/Value 儲存系統。
* **HAProxy**：提供負載平衡器。
* **Keepalived**：提供虛擬網路位址(VIP)。

### 部署與設定
首先在`所有 master 節點`下載部署元件的 YAML 檔案，這邊不採用二進制執行檔與 Systemd 來管理這些元件，全部採用 [Static Pod](https://kubernetes.io/docs/tasks/administer-cluster/static-pod/) 來達成。這邊將檔案下載至`/etc/kubernetes/manifests`目錄：
```sh
$ export CORE_URL="https://kairen.github.io/files/manual-v1.10/master"
$ mkdir -p /etc/kubernetes/manifests && cd /etc/kubernetes/manifests
$ for FILE in kube-apiserver kube-controller-manager kube-scheduler haproxy keepalived etcd etcd.config; do
    wget "${CORE_URL}/${FILE}.yml.conf" -O ${FILE}.yml
    if [ ${FILE} == "etcd.config" ]; then
      mv etcd.config.yml /etc/etcd/etcd.config.yml
      sed -i "s/\${HOSTNAME}/${HOSTNAME}/g" /etc/etcd/etcd.config.yml
      sed -i "s/\${PUBLIC_IP}/$(hostname -i)/g" /etc/etcd/etcd.config.yml
    fi
  done

$ ls /etc/kubernetes/manifests
etcd.yml  haproxy.yml  keepalived.yml  kube-apiserver.yml  kube-controller-manager.yml  kube-scheduler.yml
```
> * 若`IP`與教學設定不同的話，請記得修改 YAML 檔案。
> * kube-apiserver 中的 `NodeRestriction` 請參考 [Using Node Authorization](https://kubernetes.io/docs/admin/authorization/node/)。

產生一個用來加密 Etcd 的 Key：
```sh
$ head -c 32 /dev/urandom | base64
SUpbL4juUYyvxj3/gonV5xVEx8j769/99TSAf8YT/sQ=
```
> 注意每台`master`節點需要用一樣的 Key。

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

下載`haproxy.cfg`檔案來提供給 HAProxy 容器使用：
```sh
$ mkdir -p /etc/haproxy/
$ wget "${CORE_URL}/haproxy.cfg" -O /etc/haproxy/haproxy.cfg
```
> 若與本教學 IP 不同的話，請記得修改設定檔。

下載`kubelet.service`相關檔案來管理 kubelet：
```sh
$ mkdir -p /etc/systemd/system/kubelet.service.d
$ wget "${CORE_URL}/kubelet.service" -O /lib/systemd/system/kubelet.service
$ wget "${CORE_URL}/10-kubelet.conf" -O /etc/systemd/system/kubelet.service.d/10-kubelet.conf
```
> 若 cluster `dns`或`domain`有改變的話，需要修改`10-kubelet.conf`。

最後建立 var 存放資訊，然後啟動 kubelet 服務:
```sh
$ mkdir -p /var/lib/kubelet /var/log/kubernetes /var/lib/etcd
$ systemctl enable kubelet.service && systemctl start kubelet.service
```

完成後會需要一段時間來下載映像檔與啟動元件，可以利用該指令來監看：
```sh
$ watch netstat -ntlp
Active Internet connections (only servers)
Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name
tcp        0      0 127.0.0.1:10248         0.0.0.0:*               LISTEN      10344/kubelet
tcp        0      0 127.0.0.1:10251         0.0.0.0:*               LISTEN      11324/kube-schedule
tcp        0      0 0.0.0.0:6443            0.0.0.0:*               LISTEN      11416/haproxy
tcp        0      0 127.0.0.1:10252         0.0.0.0:*               LISTEN      11235/kube-controll
tcp        0      0 0.0.0.0:9090            0.0.0.0:*               LISTEN      11416/haproxy
tcp6       0      0 :::2379                 :::*                    LISTEN      10479/etcd
tcp6       0      0 :::2380                 :::*                    LISTEN      10479/etcd
tcp6       0      0 :::10255                :::*                    LISTEN      10344/kubelet
tcp6       0      0 :::5443                 :::*                    LISTEN      11295/kube-apiserve
```
> 若看到以上資訊表示服務正常啟動，若發生問題可以用`docker`指令來查看。

### 驗證叢集
完成後，在任意一台`master`節點複製 admin kubeconfig 檔案，並透過簡單指令驗證：
```sh
$ cp /etc/kubernetes/admin.conf ~/.kube/config
$ kubectl get cs
NAME                 STATUS    MESSAGE              ERROR
controller-manager   Healthy   ok
scheduler            Healthy   ok
etcd-2               Healthy   {"health": "true"}
etcd-1               Healthy   {"health": "true"}
etcd-0               Healthy   {"health": "true"}

$ kubectl get node
NAME      STATUS     ROLES     AGE       VERSION
k8s-m1    NotReady   master    52s       v1.10.0
k8s-m2    NotReady   master    51s       v1.10.0
k8s-m3    NotReady   master    50s       v1.10.0

$ kubectl -n kube-system get po
NAME                             READY     STATUS    RESTARTS   AGE
etcd-k8s-m1                      1/1       Running   0          7s
etcd-k8s-m2                      1/1       Running   0          57s
haproxy-k8s-m3                   1/1       Running   0          1m
...
```

接著確認服務能夠執行 logs 等指令：
```sh
$ kubectl -n kube-system logs -f kube-scheduler-k8s-m2
Error from server (Forbidden): Forbidden (user=kube-apiserver, verb=get, resource=nodes, subresource=proxy) ( pods/log kube-scheduler-k8s-m2)
```
> 這邊會發現出現 403 Forbidden 問題，這是因為 `kube-apiserver` user 並沒有 nodes 的資源存取權限，屬於正常。

由於上述權限問題，必需建立一個`apiserver-to-kubelet-rbac.yml`來定義權限，以供對 Nodes 容器執行 logs、exec 等指令。在任意一台`master`節點執行以下指令：
```sh
$ kubectl apply -f "${CORE_URL}/apiserver-to-kubelet-rbac.yml.conf"
clusterrole.rbac.authorization.k8s.io "system:kube-apiserver-to-kubelet" configured
clusterrolebinding.rbac.authorization.k8s.io "system:kube-apiserver" configured

# 測試 logs
$ kubectl -n kube-system logs -f kube-scheduler-k8s-m2
...
I0403 02:30:36.375935       1 server.go:555] Version: v1.10.0
I0403 02:30:36.378208       1 server.go:574] starting healthz server on 127.0.0.1:10251
```

設定`master`節點允許 Taint：
```sh
$ kubectl taint nodes node-role.kubernetes.io/master="":NoSchedule --all
node "k8s-m1" tainted
node "k8s-m2" tainted
node "k8s-m3" tainted
```
> [Taints and Tolerations](https://kubernetes.io/docs/concepts/configuration/taint-and-toleration/)。

### 建立 TLS Bootstrapping RBAC 與 Secret
由於本次安裝啟用了 TLS 認證，因此每個節點的 kubelet 都必須使用 kube-apiserver 的 CA 的憑證後，才能與 kube-apiserver 進行溝通，而該過程需要手動針對每台節點單獨簽署憑證是一件繁瑣的事情，且一旦節點增加會延伸出管理不易問題; 而 TLS bootstrapping 目標就是解決該問題，透過讓 kubelet 先使用一個預定低權限使用者連接到 kube-apiserver，然後在對 kube-apiserver 申請憑證簽署，當授權 Token 一致時，Node 節點的 kubelet 憑證將由 kube-apiserver 動態簽署提供。具體作法可以參考 [TLS Bootstrapping](https://kubernetes.io/docs/admin/kubelet-tls-bootstrapping/) 與 [Authenticating with Bootstrap Tokens](https://kubernetes.io/docs/admin/bootstrap-tokens/)。

首先在`k8s-m1`建立一個變數來產生`BOOTSTRAP_TOKEN`，並建立`bootstrap-kubelet.conf`的 Kubernetes config 檔：
```sh
$ cd /etc/kubernetes/pki
$ export TOKEN_ID=$(openssl rand 3 -hex)
$ export TOKEN_SECRET=$(openssl rand 8 -hex)
$ export BOOTSTRAP_TOKEN=${TOKEN_ID}.${TOKEN_SECRET}
$ export KUBE_APISERVER="https://192.16.35.10:6443"

# bootstrap set cluster
$ kubectl config set-cluster kubernetes \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=${KUBE_APISERVER} \
    --kubeconfig=../bootstrap-kubelet.conf

# bootstrap set credentials
$ kubectl config set-credentials tls-bootstrap-token-user \
    --token=${BOOTSTRAP_TOKEN} \
    --kubeconfig=../bootstrap-kubelet.conf

# bootstrap set context
$ kubectl config set-context tls-bootstrap-token-user@kubernetes \
    --cluster=kubernetes \
    --user=tls-bootstrap-token-user \
    --kubeconfig=../bootstrap-kubelet.conf

# bootstrap use default context
$ kubectl config use-context tls-bootstrap-token-user@kubernetes \
    --kubeconfig=../bootstrap-kubelet.conf
```
> 若想要用手動簽署憑證來進行授權的話，可以參考 [Certificate](https://kubernetes.io/docs/concepts/cluster-administration/certificates/)。

接著在`k8s-m1`建立 TLS bootstrap secret 來提供自動簽證使用：
```sh
$ cat <<EOF | kubectl create -f -
apiVersion: v1
kind: Secret
metadata:
  name: bootstrap-token-${TOKEN_ID}
  namespace: kube-system
type: bootstrap.kubernetes.io/token
stringData:
  token-id: ${TOKEN_ID}
  token-secret: ${TOKEN_SECRET}
  usage-bootstrap-authentication: "true"
  usage-bootstrap-signing: "true"
  auth-extra-groups: system:bootstrappers:default-node-token
EOF

secret "bootstrap-token-65a3a9" created
```

在`k8s-m1`建立 TLS Bootstrap Autoapprove RBAC：
```sh
$ kubectl apply -f "${CORE_URL}/kubelet-bootstrap-rbac.yml.conf"
clusterrolebinding.rbac.authorization.k8s.io "kubelet-bootstrap" created
clusterrolebinding.rbac.authorization.k8s.io "node-autoapprove-bootstrap" created
clusterrolebinding.rbac.authorization.k8s.io "node-autoapprove-certificate-rotation" created
```

## Kubernetes Nodes
本部分將說明如何建立與設定 Kubernetes Node 角色，Node 是主要執行容器實例(Pod)的工作節點。

在開始部署前，先在`k8-m1`將需要用到的檔案複製到所有`node`節點上：
```sh
$ cd /etc/kubernetes/pki
$ for NODE in k8s-n1 k8s-n2 k8s-n3; do
    echo "--- $NODE ---"
    ssh ${NODE} "mkdir -p /etc/kubernetes/pki/"
    ssh ${NODE} "mkdir -p /etc/etcd/ssl"
    # Etcd
    for FILE in etcd-ca.pem etcd.pem etcd-key.pem; do
      scp /etc/etcd/ssl/${FILE} ${NODE}:/etc/etcd/ssl/${FILE}
    done
    # Kubernetes
    for FILE in pki/ca.pem pki/ca-key.pem bootstrap-kubelet.conf; do
      scp /etc/kubernetes/${FILE} ${NODE}:/etc/kubernetes/${FILE}
    done
  done
```

### 部署與設定
在每台`node`節點下載`kubelet.service`相關檔案來管理 kubelet：
```sh
$ export CORE_URL="https://kairen.github.io/files/manual-v1.10/node"
$ mkdir -p /etc/systemd/system/kubelet.service.d
$ wget "${CORE_URL}/kubelet.service" -O /lib/systemd/system/kubelet.service
$ wget "${CORE_URL}/10-kubelet.conf" -O /etc/systemd/system/kubelet.service.d/10-kubelet.conf
```
> 若 cluster `dns`或`domain`有改變的話，需要修改`10-kubelet.conf`。

最後建立 var 存放資訊，然後啟動 kubelet 服務:
```sh
$ mkdir -p /var/lib/kubelet /var/log/kubernetes
$ systemctl enable kubelet.service && systemctl start kubelet.service
```

### 驗證叢集
完成後，在任意一台`master`節點並透過簡單指令驗證：
```sh
$ kubectl get csr
NAME                                                   AGE       REQUESTOR                 CONDITION
csr-bvz9l                                              11m       system:node:k8s-m1        Approved,Issued
csr-jwr8k                                              11m       system:node:k8s-m2        Approved,Issued
csr-q867w                                              11m       system:node:k8s-m3        Approved,Issued
node-csr-Y-FGvxZWJqI-8RIK_IrpgdsvjGQVGW0E4UJOuaU8ogk   17s       system:bootstrap:dca3e1   Approved,Issued
node-csr-cnX9T1xp1LdxVDc9QW43W0pYkhEigjwgceRshKuI82c   19s       system:bootstrap:dca3e1   Approved,Issued
node-csr-m7SBA9RAGCnsgYWJB-u2HoB2qLSfiQZeAxWFI2WYN7Y   18s       system:bootstrap:dca3e1   Approved,Issued

$ kubectl get nodes
NAME      STATUS     ROLES     AGE       VERSION
k8s-m1    NotReady   master    12m       v1.10.0
k8s-m2    NotReady   master    11m       v1.10.0
k8s-m3    NotReady   master    11m       v1.10.0
k8s-n1    NotReady   node      32s       v1.10.0
k8s-n2    NotReady   node      31s       v1.10.0
k8s-n3    NotReady   node      29s       v1.10.0
```

## Kubernetes Core Addons 部署
當完成上面所有步驟後，接著需要部署一些插件，其中如`Kubernetes DNS`與`Kubernetes Proxy`等這種 Addons 是非常重要的。

### Kubernetes Proxy
[Kube-proxy](https://github.com/kubernetes/kubernetes/tree/master/cluster/addons/kube-proxy) 是實現 Service 的關鍵插件，kube-proxy 會在每台節點上執行，然後監聽 API Server 的 Service 與 Endpoint 資源物件的改變，然後來依據變化執行 iptables 來實現網路的轉發。

在`k8s-m1`下載`kube-proxy.yml`來建立 Kubernetes Proxy Addon：
```sh
$ kubectl apply -f "https://kairen.github.io/files/manual-v1.10/addon/kube-proxy.yml.conf"
serviceaccount "kube-proxy" created
clusterrolebinding.rbac.authorization.k8s.io "system:kube-proxy" created
configmap "kube-proxy" created
daemonset.apps "kube-proxy" created

$ kubectl -n kube-system get po -o wide -l k8s-app=kube-proxy
NAME               READY     STATUS    RESTARTS   AGE       IP             NODE
kube-proxy-8j5w8   1/1       Running   0          29s       192.16.35.16   k8s-n3
kube-proxy-c4zvt   1/1       Running   0          29s       192.16.35.11   k8s-m1
kube-proxy-clpl6   1/1       Running   0          29s       192.16.35.12   k8s-m2
...
```

### Kubernetes DNS
[Kube DNS](https://github.com/kubernetes/kubernetes/tree/master/cluster/addons/dns) 是 Kubernetes 叢集內部 Pod 之間互相溝通的重要 Addon，它允許 Pod 可以透過 Domain Name 方式來連接 Service，其主要由 Kube DNS 與 Sky DNS 組合而成，透過 Kube DNS 監聽 Service 與 Endpoint 變化，來提供給 Sky DNS 資訊，已更新解析位址。

在`k8s-m1`下載`kube-proxy.yml`來建立 Kubernetes Proxy Addon：
```sh
$ kubectl apply -f "https://kairen.github.io/files/manual-v1.10/addon/kube-dns.yml.conf"
serviceaccount "kube-dns" created
service "kube-dns" created
deployment.extensions "kube-dns" created

$ kubectl -n kube-system get po -l k8s-app=kube-dns
NAME                        READY     STATUS    RESTARTS   AGE
kube-dns-654684d656-zq5t8   0/3       Pending   0          1m
```

這邊會發現處於`Pending`狀態，是由於 Kubernetes Pod Network 還未建立完成，因此所有節點會處於`NotReady`狀態，而造成 Pod 無法被排程分配到指定節點上啟動，由於為了解決該問題，下節將說明如何建立 Pod Network。

## Calico Network 安裝與設定
Calico 是一款純 Layer 3 的資料中心網路方案(不需要 Overlay 網路)，Calico 好處是它整合了各種雲原生平台，且 Calico 在每一個節點利用 Linux Kernel 實現高效的 vRouter 來負責資料的轉發，而當資料中心複雜度增加時，可以用 BGP route reflector 來達成。

> 本次不採用手動方式來建立 Calico 網路，若想了解可以參考 [Integration Guide](https://docs.projectcalico.org/v3.0/getting-started/kubernetes/installation/integration)。

在`k8s-m1`下載`calico.yaml`來建立 Calico Network：
```sh
$ kubectl apply -f "https://kairen.github.io/files/manual-v1.10/network/calico.yml.conf"
configmap "calico-config" created
daemonset "calico-node" created
deployment "calico-kube-controllers" created
clusterrolebinding "calico-cni-plugin" created
clusterrole "calico-cni-plugin" created
serviceaccount "calico-cni-plugin" created
clusterrolebinding "calico-kube-controllers" created
clusterrole "calico-kube-controllers" created
serviceaccount "calico-kube-controllers" created

$ kubectl -n kube-system get po -l k8s-app=calico-node -o wide
NAME                READY     STATUS    RESTARTS   AGE       IP             NODE
calico-node-22mbb   2/2       Running   0          1m        192.16.35.12   k8s-m2
calico-node-2qwf5   2/2       Running   0          1m        192.16.35.11   k8s-m1
calico-node-g2sp8   2/2       Running   0          1m        192.16.35.13   k8s-m3
calico-node-hghp4   2/2       Running   0          1m        192.16.35.14   k8s-n1
calico-node-qp6gf   2/2       Running   0          1m        192.16.35.15   k8s-n2
calico-node-zfx4n   2/2       Running   0          1m        192.16.35.16   k8s-n3
```
> 這邊若節點 IP 與網卡不同的話，請修改`calico.yml`檔案。

在`k8s-m1`下載 Calico CLI 來查看 Calico nodes:
```sh
$ wget https://github.com/projectcalico/calicoctl/releases/download/v3.1.0/calicoctl -O /usr/local/bin/calicoctl
$ chmod u+x /usr/local/bin/calicoctl
$ cat <<EOF > ~/calico-rc
export ETCD_ENDPOINTS="https://192.16.35.11:2379,https://192.16.35.12:2379,https://192.16.35.13:2379"
export ETCD_CA_CERT_FILE="/etc/etcd/ssl/etcd-ca.pem"
export ETCD_CERT_FILE="/etc/etcd/ssl/etcd.pem"
export ETCD_KEY_FILE="/etc/etcd/ssl/etcd-key.pem"
EOF

$ . ~/calico-rc
$ calicoctl node status
Calico process is running.

IPv4 BGP status
+--------------+-------------------+-------+----------+-------------+
| PEER ADDRESS |     PEER TYPE     | STATE |  SINCE   |    INFO     |
+--------------+-------------------+-------+----------+-------------+
| 192.16.35.12 | node-to-node mesh | up    | 04:42:37 | Established |
| 192.16.35.13 | node-to-node mesh | up    | 04:42:42 | Established |
| 192.16.35.14 | node-to-node mesh | up    | 04:42:37 | Established |
| 192.16.35.15 | node-to-node mesh | up    | 04:42:41 | Established |
| 192.16.35.16 | node-to-node mesh | up    | 04:42:36 | Established |
+--------------+-------------------+-------+----------+-------------+
...
```

查看 pending 的 pod 是否已執行：
```sh
$ kubectl -n kube-system get po -l k8s-app=kube-dns
kubectl -n kube-system get po -l k8s-app=kube-dns
NAME                        READY     STATUS    RESTARTS   AGE
kube-dns-654684d656-j8xzx   3/3       Running   0          10m
```

## Kubernetes Extra Addons 部署
本節說明如何部署一些官方常用的 Addons，如 Dashboard、Heapster 等。

### Dashboard
[Dashboard](https://github.com/kubernetes/dashboard) 是 Kubernetes 社區官方開發的儀表板，有了儀表板後管理者就能夠透過 Web-based 方式來管理 Kubernetes 叢集，除了提升管理方便，也讓資源視覺化，讓人更直覺看見系統資訊的呈現結果。

在`k8s-m1`透過 kubectl 來建立 kubernetes dashboard 即可：
```sh
$ kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/master/src/deploy/recommended/kubernetes-dashboard.yaml
$ kubectl -n kube-system get po,svc -l k8s-app=kubernetes-dashboard
NAME                                    READY     STATUS    RESTARTS   AGE
kubernetes-dashboard-7d5dcdb6d9-j492l   1/1       Running   0          12s

NAME                   TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
kubernetes-dashboard   ClusterIP   10.111.22.111   <none>        443/TCP   12s
```

這邊會額外建立一個名稱為`open-api` Cluster Role Binding，這僅作為方便測試時使用，在一般情況下不要開啟，不然就會直接被存取所有 API:
```sh
$ cat <<EOF | kubectl create -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: open-api
  namespace: ""
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: system:anonymous
EOF
```
> 注意!管理者可以針對特定使用者來開放 API 存取權限，但這邊方便使用直接綁在 cluster-admin cluster role。

完成後，就可以透過瀏覽器存取 [Dashboard](https://192.16.35.10:6443/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/)。

在 1.7 版本以後的 Dashboard 將不再提供所有權限，因此需要建立一個 service account 來綁定 cluster-admin role：
```sh
$ kubectl -n kube-system create sa dashboard
$ kubectl create clusterrolebinding dashboard --clusterrole cluster-admin --serviceaccount=kube-system:dashboard
$ SECRET=$(kubectl -n kube-system get sa dashboard -o yaml | awk '/dashboard-token/ {print $3}')
$ kubectl -n kube-system describe secrets ${SECRET} | awk '/token:/{print $2}'
eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJrdWJlcm5ldGVzL3NlcnZpY2VhY2NvdW50Iiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9uYW1lc3BhY2UiOiJrdWJlLXN5c3RlbSIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VjcmV0Lm5hbWUiOiJkYXNoYm9hcmQtdG9rZW4tdzVocmgiLCJrdWJlcm5ldGVzLmlvL3NlcnZpY2VhY2NvdW50L3NlcnZpY2UtYWNjb3VudC5uYW1lIjoiZGFzaGJvYXJkIiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9zZXJ2aWNlLWFjY291bnQudWlkIjoiYWJmMTFjYzMtZjRlYi0xMWU3LTgzYWUtMDgwMDI3NjdkOWI5Iiwic3ViIjoic3lzdGVtOnNlcnZpY2VhY2NvdW50Omt1YmUtc3lzdGVtOmRhc2hib2FyZCJ9.Xuyq34ci7Mk8bI97o4IldDyKySOOqRXRsxVWIJkPNiVUxKT4wpQZtikNJe2mfUBBD-JvoXTzwqyeSSTsAy2CiKQhekW8QgPLYelkBPBibySjBhJpiCD38J1u7yru4P0Pww2ZQJDjIxY4vqT46ywBklReGVqY3ogtUQg-eXueBmz-o7lJYMjw8L14692OJuhBjzTRSaKW8U2MPluBVnD7M2SOekDff7KpSxgOwXHsLVQoMrVNbspUCvtIiEI1EiXkyCNRGwfnd2my3uzUABIHFhm0_RZSmGwExPbxflr8Fc6bxmuz-_jSdOtUidYkFIzvEWw2vRovPgs3MXTv59RwUw
```
> 複製`token`，然後貼到 Kubernetes dashboard。注意這邊一般來說要針對不同 User 開啟特定存取權限。

![](/images/kube/kubernetes-dashboard.png)

### Heapster
[Heapster](https://github.com/kubernetes/heapster) 是 Kubernetes 社區維護的容器叢集監控與效能分析工具。Heapster 會從 Kubernetes apiserver 取得所有 Node 資訊，然後再透過這些 Node 來取得 kubelet 上的資料，最後再將所有收集到資料送到 Heapster 的後台儲存 InfluxDB，最後利用 Grafana 來抓取 InfluxDB 的資料源來進行視覺化。

在`k8s-m1`透過 kubectl 來建立 kubernetes monitor  即可：
```sh
$ kubectl apply -f "https://kairen.github.io/files/manual-v1.10/addon/kube-monitor.yml.conf"
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

完成後，就可以透過瀏覽器存取 [Grafana Dashboard](https://192.16.35.10:6443/api/v1/namespaces/kube-system/services/monitoring-grafana/proxy/)。

![](/images/kube/monitoring-grafana.png)

### Ingress Controller
[Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)是利用 Nginx 或 HAProxy 等負載平衡器來曝露叢集內服務的元件，Ingress 主要透過設定 Ingress 規則來定義 Domain Name 映射 Kubernetes 內部 Service，這種方式可以避免掉使用過多的 NodePort 問題。

在`k8s-m1`透過 kubectl 來建立 Ingress Controller 即可：
```sh
$ kubectl create ns ingress-nginx
$ kubectl apply -f "https://kairen.github.io/files/manual-v1.10/addon/ingress-controller.yml.conf"
$ kubectl -n ingress-nginx get po
NAME                                       READY     STATUS    RESTARTS   AGE
default-http-backend-5c6d95c48-rzxfb       1/1       Running   0          7m
nginx-ingress-controller-699cdf846-982n4   1/1       Running   0          7m
```
> 這裡也可以選擇 [Traefik](https://github.com/containous/traefik) 的 Ingress Controller。

#### 測試 Ingress 功能
這邊先建立一個 Nginx HTTP server Deployment 與 Service：
```sh
$ kubectl run nginx-dp --image nginx --port 80
$ kubectl expose deploy nginx-dp --port 80
$ kubectl get po,svc
$ cat <<EOF | kubectl create -f -
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: test-nginx-ingress
  annotations:
    ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: test.nginx.com
    http:
      paths:
      - path: /
        backend:
          serviceName: nginx-dp
          servicePort: 80
EOF
```

透過 curl 來進行測試：
```sh
$ curl 192.16.35.10 -H 'Host: test.nginx.com'
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
...

# 測試其他 domain name 是否會回傳 404
$ curl 192.16.35.10 -H 'Host: test.nginx.com1'
default backend - 404
```

### Helm Tiller Server
[Helm](https://github.com/kubernetes/helm) 是 Kubernetes Chart 的管理工具，Kubernetes Chart 是一套預先組態的 Kubernetes 資源套件。其中`Tiller Server`主要負責接收來至 Client 的指令，並透過 kube-apiserver 與 Kubernetes 叢集做溝通，根據 Chart 定義的內容，來產生與管理各種對應 API 物件的 Kubernetes 部署檔案(又稱為 `Release`)。

首先在`k8s-m1`安裝 Helm tool：
```sh
$ wget -qO- https://kubernetes-helm.storage.googleapis.com/helm-v2.8.1-linux-amd64.tar.gz | tar -zx
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
NAME                             READY     STATUS    RESTARTS   AGE
tiller-deploy-5f789bd9f7-tzss6   1/1       Running   0          29s

$ helm version
Client: &version.Version{SemVer:"v2.8.1", GitCommit:"6af75a8fd72e2aa18a2b278cfe5c7a1c5feca7f2", GitTreeState:"clean"}
Server: &version.Version{SemVer:"v2.8.1", GitCommit:"6af75a8fd72e2aa18a2b278cfe5c7a1c5feca7f2", GitTreeState:"clean"}
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

完成後，就可以透過瀏覽器存取 [Jenkins Web](http://192.16.35.10:31161)。

![](/images/kube/helm-jenkins-v1.10.png)

測試完成後，即可刪除：
```sh
$ helm ls
NAME	REVISION	UPDATED                 	STATUS  	CHART         	NAMESPACE
demo	1       	Tue Apr 10 07:29:51 2018	DEPLOYED	jenkins-0.14.4	default

$ helm delete demo --purge
release "demo" deleted
```

更多 Helm Apps 可以到 [Kubeapps Hub](https://hub.kubeapps.com/) 尋找。

## 測試叢集
SSH 進入`k8s-m1`節點，然後關閉該節點：
```sh
$ sudo poweroff
```

接著進入到`k8s-m2`節點，透過 kubectl 來檢查叢集是否能夠正常執行：
```sh
# 先檢查 etcd 狀態，可以發現 etcd-0 因為關機而中斷
$ kubectl get cs
NAME                 STATUS      MESSAGE                                                                                                                                          ERROR
scheduler            Healthy     ok
controller-manager   Healthy     ok
etcd-1               Healthy     {"health": "true"}
etcd-2               Healthy     {"health": "true"}
etcd-0               Unhealthy   Get https://192.16.35.11:2379/health: net/http: request canceled while waiting for connection (Client.Timeout exceeded while awaiting headers)

# 測試是否可以建立 Pod
$ kubectl run nginx --image nginx --restart=Never --port 80
$ kubectl get po
NAME      READY     STATUS    RESTARTS   AGE
nginx     1/1       Running   0          22s
```
