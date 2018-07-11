---
title: 使用 kubefed 建立 Kubernetes Federation(On-premises)
date: 2018-3-21 17:08:54
catalog: true
categories:
- Kubernetes
tags:
- Kubernetes
- Federation
---
[Kubernetes Federation(聯邦)](https://kubernetes.io/docs/concepts/cluster-administration/federation/) 是實現跨地區與跨服務商多個 Kubernetes 叢集的管理機制。Kubernetes Federation 的架構非常類似純 Kubenretes 叢集，Federation 會擁有自己的 API Server 與 Controller Manager 來提供一個標準的 Kubernetes API，以及管理聯邦叢集，並利用 Etcd 來儲存所有狀態，不過差異在於 Kubenretes 只管理多個節點，而 Federation 是管理所有被註冊的 Kubernetes 叢集。

<!--more-->

Federation 使管理多個叢集更為簡單，這主要是透過兩個模型來實現：
1. **跨叢集的資源同步(Sync resources across clusters)**：提供在多個叢集中保持資源同步的功能，如確保一個 Deployment 可以存在於多個叢集中。
2. **跨叢集的服務發現(Cross cluster discovery:)**：提供自動配置 DNS 服務以及在所有叢集後端上進行負載平衡功能，如提供全域 VIP 或 DNS record，並透過此存取多個叢集後端。

![](/images/kube/federation-api.png)

Federation 有以下幾個好處：
1. 跨叢集的資源排程，能讓 Pod 分配至不同叢集的不同節點上執行，如果當前叢集超出負荷，能夠將額外附載分配到空閒叢集上。
2. 叢集的高可靠，能夠做到 Pod 故障自動遷移。
3. 可管理多個 Kubernetes 叢集。
4. 跨叢集的服務發現。

> 雖然 Federation 能夠降低管理多叢集門檻，但是目前依據不建議放到生產環境。以下幾個原因：
* **成熟度問題**，目前還處與 Alpha 階段，故很多功能都還處於實現性質，或者不太穩定。
* **提升網路頻寬與成本**，由於 Federation 需要監控所有叢集以確保當前狀態符合預期，因是會增加額外效能開銷。
* **跨叢集隔離差**，Federation 的子叢集git有可能因為 Bug 的引發而影響其他叢集運行狀況。
* 個人用起來不是很穩定，例如建立的 Deployment 刪除很常會 Timeout。
* 支援的物件資源有限，如不支援 StatefulSets。可參考 [API resources](https://kubernetes.io/docs/concepts/cluster-administration/federation/#api-resources)。

Federation 主要包含三個元件：
* **federation-apiserver**：主要提供跨叢集的 REST API 伺服器，類似 kube-apiserver。
* **federation-controller-manager**：提供多個叢集之間的狀態同步，類似 kube-controller-manager。
* **kubefed**：Federation CLI 工具，用來初始化 Federation 元件與加入子叢集。

## 節點資訊
本次安裝作業系統採用`Ubuntu 16.04 Server`，測試環境為實體機器，共有三組叢集：

Federation 控制平面叢集(簡稱 F):

| IP Address    | Host     | vCPU | RAM |
|---------------|----------|------|-----|
| 172.22.132.31 | k8s-f-m1 | 4    | 16G |
| 172.22.132.32 | k8s-f-n1 | 4    | 16G |

叢集 A:

| IP Address    | Host     | vCPU | RAM |
|---------------|----------|------|-----|
| 172.22.132.41 | k8s-a-m1 | 8    | 16G |
| 172.22.132.42 | k8s-a-n1 | 8    | 16G |

叢集 B:

| IP Address    | Host     | vCPU | RAM |
|---------------|----------|------|-----|
| 172.22.132.51 | k8s-b-m1 | 8    | 16G |
| 172.22.132.52 | k8s-b-n1 | 8    | 16G |


## 事前準備
安裝與進行 Federation 之前，需要確保以下條件達成：
* 所有叢集的節點各自部署成一個 Kubernetes 叢集，請參考 [用 kubeadm 部署 Kubernetes 叢集](https://kairen.github.io/2016/09/29/kubernetes/deploy/kubeadm/)。
* 修改 F、A 與 B 叢集的 Kubernetes config，並將 A 與 B 複製到 F 節點，如修改成以下：

```yaml
...
...
  name: k8s-a-cluster
contexts:
- context:
    cluster: k8s-a-cluster
    user: a-cluster-admin
  name: a-cluster-context
current-context: a-cluster-context
kind: Config
preferences: {}
users:
- name: a-cluster-admin
  user:
...
```
> 這邊需要修改每個叢集 config。

* 接著在 F 叢集合併 F、A 與 B 三個 config，透過以下方式進行：

```sh
$ ls
a-cluster.conf  b-cluster.conf  f-cluster.conf

$ KUBECONFIG=f-cluster.conf:a-cluster.conf:b-cluster.conf kubectl config view --flatten > ~/.kube/config
$ kubectl config get-contexts
CURRENT   NAME                CLUSTER         AUTHINFO          NAMESPACE
          a-cluster-context   k8s-a-cluster   a-cluster-admin
          b-cluster-context   k8s-b-cluster   b-cluster-admin
*         f-cluster-context   k8s-f-cluster   f-cluster-admin
```

* 在 F 叢集安裝 kubefed 工具：

```sh
$ wget https://storage.googleapis.com/kubernetes-federation-release/release/v1.9.0-alpha.3/federation-client-linux-amd64.tar.gz
$ tar xvf federation-client-linux-amd64.tar.gz
$ cp federation/client/bin/kubefed /usr/local/bin/
$ kubefed version
Client Version: version.Info{Major:"1", Minor:"9+", GitVersion:"v1.9.0-alpha.3", GitCommit:"85c06145286da663755b140efa2b65f793cce9ec", GitTreeState:"clean", BuildDate:"2018-02-14T12:54:40Z", GoVersion:"go1.9.1", Compiler:"gc", Platform:"linux/amd64"}
Server Version: version.Info{Major:"1", Minor:"9", GitVersion:"v1.9.6", GitCommit:"9f8ebd171479bec0ada837d7ee641dec2f8c6dd1", GitTreeState:"clean", BuildDate:"2018-03-21T15:13:31Z", GoVersion:"go1.9.3", Compiler:"gc", Platform:"linux/amd64"}
```

* 在 F 叢集安裝 Helm 工具，並進行初始化：

```sh
$ wget -qO- https://kubernetes-helm.storage.googleapis.com/helm-v2.8.1-linux-amd64.tar.gz | tar -zxf
$ sudo mv linux-amd64/helm /usr/local/bin/
$ kubectl -n kube-system create sa tiller
$ kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller
$ helm init --service-account tiller

# wait for a few minutes
$ helm version
Client: &version.Version{SemVer:"v2.8.1", GitCommit:"6af75a8fd72e2aa18a2b278cfe5c7a1c5feca7f2", GitTreeState:"clean"}
Server: &version.Version{SemVer:"v2.8.1", GitCommit:"6af75a8fd72e2aa18a2b278cfe5c7a1c5feca7f2", GitTreeState:"clean"}
```

## 部署 Kubernetes Federation
由於本篇是使用實體機器部署 Kubernetes 叢集，因此無法像是 GCP 可以提供 DNS 服務來給 Federation 使用，故這邊要用 CoreDNS 建立自定義 DNS 服務。

### CoreDNS 安裝
首先透過 Helm 來安裝 CoreDNS 使用到的 Etcd：
```sh
$ helm install --namespace federation --name etcd-operator stable/etcd-operator
$ helm upgrade --namespace federation --set cluster.enabled=true etcd-operator stable/etcd-operator
$ kubectl -n federation get po
NAME                                                              READY     STATUS    RESTARTS   AGE
etcd-operator-etcd-operator-etcd-backup-operator-577d56449zqkj2   1/1       Running   0          1m
etcd-operator-etcd-operator-etcd-operator-56679fb56-fpgmm         1/1       Running   0          1m
etcd-operator-etcd-operator-etcd-restore-operator-65b6cbccl7kzr   1/1       Running   0          1m
```

完成後就可以安裝 CoreDNS 來提供自定義 DNS 服務了：
```sh
$ cat <<EOF > Values.yaml
isClusterService: false
serviceType: NodePort
middleware:
  kubernetes:
    enabled: false
  etcd:
    enabled: true
    zones:
    - "kairen.com."
    endpoint: "http://etcd-cluster.federation:2379"
EOF

$ kubectl create clusterrolebinding federation-admin --clusterrole=cluster-admin --user=system:serviceaccount:federation:default
$ helm install --namespace federation --name coredns -f Values.yaml stable/coredns
# 測試 CoreDNS 可以查詢 Domain Name
$ kubectl run -it --rm --restart=Never --image=infoblox/dnstools:latest dnstools
dnstools# host kubernetes
kubernetes.default.svc.cluster.local has address 10.96.0.1
```

### 安裝與初始化 Federation 控制平面元件
完成 CoreDNS 後，接著透過 kubefed 安裝控制平面元件，由於使用到 CoreDNS，因此這邊要傳入相關 conf 檔，首先建立`coredns-provider.conf`檔案，加入以下內容：
```sh
$ cat <<EOF > coredns-provider.conf
[Global]
etcd-endpoints = http://etcd-cluster.federation:2379
zones = kairen.com.
EOF
```
> 請自行修改`etcd-endpoints`與`zones`。

檔案建立並確認沒問題後，透過 kubefed 工具來初始化主叢集：
```sh
$ kubefed init federation \
  --host-cluster-context=f-cluster-context \
  --dns-provider="coredns" \
  --dns-zone-name="kairen.com." \
  --apiserver-enable-basic-auth=true \
  --apiserver-enable-token-auth=true \
  --dns-provider-config="coredns-provider.conf" \
  --apiserver-arg-overrides="--anonymous-auth=false,--v=4" \
  --api-server-service-type="NodePort" \
  --api-server-advertise-address="172.22.132.31" \
  --etcd-persistent-storage=true

$ kubectl -n federation-system get po
NAME                                  READY     STATUS    RESTARTS   AGE
apiserver-848d584b5d-cwxdh            2/2       Running   0          1m
controller-manager-5846c555c6-mw2jz   1/1       Running   1          1m
```
> 這邊可以改變`--etcd-persistent-storage`來選擇使用或不使用 PV，若使用請先建立一個 PV 來提供給 Federation Pod 的 PVC 索取使用，可以參考 [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)。

### 加入 Federation 的 Kubernetes 子叢集
```sh
$ kubectl config use-context federation

# 加入 k8s-a-cluster
$ kubefed join f-a-cluster \
  --cluster-context=a-cluster-context \
  --host-cluster-context=f-cluster-context

# 加入 k8s-b-cluster
$ kubefed join f-b-cluster \
  --cluster-context=b-cluster-context \
  --host-cluster-context=f-cluster-context

$ kubectl get cluster
NAME          AGE
f-a-cluster   57s
f-b-cluster   53s
```

## 測試 Federation 叢集
這邊利用 Nginx Deployment 來進行測試，先簡單建立一個副本為 4 的 Nginx：
```sh
$ kubectl config use-context federation
$ kubectl create ns default
$ kubectl run nginx --image nginx --port 80 --replicas=4
```

查看 Cluster A：
```sh
$ kubectl --context=a-cluster-context get po
NAME                     READY     STATUS    RESTARTS   AGE
nginx-7587c6fdb6-dpjv5   1/1       Running   0          25s
nginx-7587c6fdb6-sjv8v   1/1       Running   0          25s
```

查看 Cluster B：
```sh
$ kubectl --context=b-cluster-context get po
NAME                     READY     STATUS    RESTARTS   AGE
nginx-7587c6fdb6-dv45v   1/1       Running   0          1m
nginx-7587c6fdb6-wxsmq   1/1       Running   0          1m
```

其他可測試功能：
- 設定 Replica set preferences，參考 [Spreading Replicas in Underlying Clusters](https://kubernetes.io/docs/tasks/administer-federation/replicaset/#spreading-replicas-in-underlying-clusters)。
- Federation 在 v1.7+ 加入了 [ClusterSelector Annotation](https://kubernetes.io/docs/tasks/administer-federation/cluster/#clusterselector-annotation)
- [Scheduling Policy](https://kubernetes.io/docs/tasks/federation/set-up-placement-policies-federation/#deploying-federation-and-configuring-an-external-policy-engine)。


## Refers
- [Minikube Federation](https://github.com/emaildanwilson/minikube-federation)
- [Global Kubernetes in 3 Steps](http://cgrant.io/tutorials/gcp/compute/gke/global-kubernetes-three-steps/)
