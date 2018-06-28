---
title: Prometheus Operator 介紹與安裝
layout: default
comments: true
date: 2018-06-23 12:23:01
categories:
- DevOps
tags:
- DevOps
- Monitoring
- CNCF
- Kubernetes
---
[Prometheus Operator](https://github.com/coreos/prometheus-operator) 是 CoreOS 開源的一套用於管理在 Kubernetes 上的 Prometheus 控制器，目標當然就是簡化部署與維護 Prometheus 上的事情，其架構如下所示：

![](https://coreos.com/sites/default/files/inline-images/p1.png)

<!--more-->

架構中的每一個部分都執行於 Kubernetes 的資源，這些資源分別負責不同作用與意義：

* **[Operator](https://coreos.com/operators/)**：Operator 是整個系統的主要控制器，會以 Deployment 方式執行於 Kubernetes 叢集上，並根據自定義的資源(Custom Resource Definition，CRDs)來負責管理與部署 Prometheus Server。而 Operator 會透過監聽這些自定義資源的事件變化來做對應處理。
* **Prometheus Server**：由 Operator 依據一個自定義資源 Prometheus 類型中，所描述的內容而部署的 Prometheus Server 叢集，可以將這個自定義資源看作是一種特別用來管理 Prometheus Server 的 StatefulSets 資源。

```yaml=
apiVersion: monitoring.coreos.com/v1
kind: Prometheus
metadata:
  name: k8s
  labels:
    prometheus: k8s
spec:
  version: v2.3.0
  replicas: 2
  serviceMonitors:
  - selector:
      matchLabels:
        k8s-app: kubelet
...
```

* **ServiceMonitor**：一個 Kubernetes 自定義資源，該資源描述了 Prometheus Server 的 Target 列表，Operator 會監聽這個資源的變化來動態的更新 Prometheus Server 的 Scrape targets。而該資源主要透過 Selector 來依據 Labels 選取對應的 Service Endpoint，並讓 Prometheus Server 透過 Service 進行拉取(Pull) Metrics 資料。

```yaml=
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: kubelet
  labels:
    k8s-app: kubelet
spec:
  jobLabel: k8s-app
  endpoints:
  - port: cadvisor
    interval: 30s # scrape the endpoint every 10 seconds
    honorLabels: true
  selector:
    matchLabels:
      k8s-app: kubelet
  namespaceSelector:
    matchNames:
    - kube-system
```
> 這是一個抓取 Cadvisor metrics 的範例。

* **Service**：Kubernetes 中的 Service 資源，這邊主要用來對應 Kubernetes 中 Metrics Server Pod，然後提供給 ServiceMonitor 選取讓 Prometheus Server 拉取資料。在 Prometheus 術語中，可以稱為 Target，即被 Prometheus 監測的對象，如一個部署在 Kubernetes 上的 Node Exporter Service。

* **Alertmanager**：Prometheus Operator 不只提供 Prometheus Server 管理與部署，也包含了 AlertManager，並且一樣透過一個 Alertmanager 自定義資源來描述資訊，再由 Operator 依據描述內容部署 Alertmanager 叢集。

```yaml=
apiVersion: monitoring.coreos.com/v1
kind: Alertmanager
metadata:
  name: main
  labels:
    alertmanager: main
spec:
  replicas: 3
...
```

## 部署 Prometheus Operator
本節將說明如何部署 Prometheus Operator 來管理 Kubernetes 上的 Prometheus 資源。

### 節點資訊
測試環境將需要一套 Kubernetes 叢集，作業系統採用`Ubuntu 16.04 Server`，測試環境為實體機器：

| IP Address    | Role   | vCPU | RAM |
|---------------|--------|------|-----|
| 172.22.132.10 | k8s-m1 | 8    | 16G |
| 172.22.132.11 | k8s-n1 | 8    | 16G |
| 172.22.132.12 | k8s-n2 | 8    | 16G |

> 這邊`m` 為 K8s master，`n`為 K8s node。

### 事前準備
開始安裝前需要確保以下條件已達成：

* 所有節點以 kubeadm 部署成 Kubernetes v1.9+ 叢集。請參考 [用 kubeadm 部署 Kubernetes 叢集](https://kairen.github.io/2016/09/29/kubernetes/deploy/kubeadm/)。

* 在 Kubernetes 叢集部署 Helm 與 Tiller server。

```shell=
$ wget -qO- https://kubernetes-helm.storage.googleapis.com/helm-v2.8.1-linux-amd64.tar.gz | tar -zx
$ sudo mv linux-amd64/helm /usr/local/bin/
$ kubectl -n kube-system create sa tiller
$ kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller
$ helm init --service-account tiller
```

* 在`k8s-m1`透過 kubectl 來建立 Ingress Controller 即可：

```shell=
$ kubectl create ns ingress-nginx
$ wget https://kairen.github.io/files/manual-v1.10/addon/ingress-controller.yml.conf -O ingress-controller.yml
$ sed -i ingress-controller.yml 's/192.16.35.10/172.22.132.10/g'
$ kubectl apply -f ingress-controller.yml.conf
```

### 部署 Prometheus Operator
Prometheus Operator 提供了多種方式部署至 Kubernetes 上，一般會使用手動(or 腳本)與 Helm 來進行部署。

#### 手動(腳本)部署
透過 Git 取得最新版本腳本：
```shell=
$ git clone https://github.com/camilb/prometheus-kubernetes.git
$ cd prometheus-kubernetes
```

接著執行`deploy`腳本來部署到 Kubernetes：
```shell=
$ ./deploy
Check for uncommitted changes

OK! No uncommitted changes detected

Creating 'monitoring' namespace.
Error from server (AlreadyExists): namespaces "monitoring" already exists

1) AWS
2) GCP
3) Azure
4) Custom
Please select your cloud provider:4
Deploying on custom providers without persistence
Setting components version
Enter Prometheus Operator version [v0.19.0]:

Enter Prometheus version [v2.2.1]:

Enter Prometheus storage retention period in hours [168h]:

Enter Prometheus storage volume size [40Gi]:

Enter Prometheus memory request in Gi or Mi [1Gi]:

Enter Grafana version [5.1.1]:

Enter Alert Manager version [v0.15.0-rc.1]:

Enter Node Exporter version [v0.16.0-rc.3]:

Enter Kube State Metrics version [v1.3.1]:

Enter Prometheus external Url [http://127.0.0.1:9090]:

Enter Alertmanager external Url [http://127.0.0.1:9093]:

Do you want to use NodeSelector  to assign monitoring components on dedicated nodes?
Y/N [N]:

Do you want to set up an SMTP relay?
Y/N [N]:

Do you want to set up slack alerts?
Y/N [N]:

# 這邊會跑一下部署階段，完成後要接著輸入一些資訊，如 Grafana username and passwd

Enter Grafana administrator username [admin]:
Enter Grafana administrator password: ******

...
Done
```
> 沒有輸入部分請直接按`Enter`。

當確認看到 Done 後就可以查看 `monitoring` namespace：
```shell=
$ kubectl -n monitoring get po
NAME                                  READY     STATUS    RESTARTS   AGE
alertmanager-main-0                   2/2       Running   0          4m
alertmanager-main-1                   2/2       Running   0          3m
alertmanager-main-2                   2/2       Running   0          3m
grafana-568b569696-nltbh              2/2       Running   0          14s
kube-state-metrics-86467959c6-kxtl4   2/2       Running   0          3m
node-exporter-526nw                   1/1       Running   0          4m
node-exporter-c828w                   1/1       Running   0          4m
node-exporter-r2qq2                   1/1       Running   0          4m
node-exporter-s25x6                   1/1       Running   0          4m
node-exporter-xpgh7                   1/1       Running   0          4m
prometheus-k8s-0                      1/2       Running   0          10s
prometheus-k8s-1                      2/2       Running   0          10s
prometheus-operator-f596c68cf-wrpqc   1/1       Running   0          4m
```

查看 Kubernetes CRDs 與 SM：
```shell=
$ kubectl -n monitoring get crd
NAME                                          AGE
alertmanagers.monitoring.coreos.com           4m
prometheuses.monitoring.coreos.com            4m
servicemonitors.monitoring.coreos.com         4m

$ kubectl -n monitoring get servicemonitors
NAME                      AGE
alertmanager              1m
kube-apiserver            1m
kube-controller-manager   1m
kube-dns                  1m
kube-scheduler            1m
kube-state-metrics        1m
kubelet                   1m
node-exporter             1m
prometheus                1m
prometheus-operator       1m
```

接著修改 Service 的 Grafana 的 Type：
```shell=
$ kubectl -n monitoring edit svc grafana
# 修改成 NodePort
```
> 也可以建立 Ingress 來存取 Grafana。
```yaml=
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  namespace: monitoring
  name: grfana-ingress
  annotations:
    ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: grafana.k8s-local.k2r2bai.com
    http:
      paths:
      - path: /
        backend:
          serviceName: grafana
          servicePort: 3000
```

:::info
這邊也可以建立 Prometheus Ingress 來使用 Web-based console。
```yaml=
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  namespace: monitoring
  name: prometheus-ingress
  annotations:
    ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: prometheus.k8s-local.k2r2bai.com
    http:
      paths:
      - path: /
        backend:
          serviceName: prometheus-k8s
          servicePort: 9090
```
:::

最後就可以存取 Grafana 來查看 Metric 視覺化資訊了。

![](https://i.imgur.com/39G6Zsm.png)

#### Helm
首先透過 Helm 加入 coreos 的 repo：
```shell=
$ helm repo add coreos https://s3-eu-west-1.amazonaws.com/coreos-charts/stable/
```

然後透過 kubectl 建立一個 Namespace 來管理 Prometheus，並用 Helm 部署 Prometheus Operator：
```shell=
$ kubectl create namespace monitoring
$ helm install coreos/prometheus-operator \
    --name prometheus-operator \
	--set rbacEnable=true \
	--namespace=monitoring
```

接著部署 Prometheus、AlertManager 與 Grafana：
```shell=
# Prometheus
$ helm install coreos/prometheus --name prometheus \
    --set serviceMonitorsSelector.app=prometheus \
	--set ruleSelector.app=prometheus \
	--namespace=monitoring

# Alert Manager
$ helm install coreos/alertmanager --name alertmanager --namespace=monitoring

# Grafana
$ helm install coreos/grafana --name grafana --namespace=monitoring
```

部署 kube-prometheus 來提供 Kubernetes 監測的 Exporter 與 ServiceMonitor：
```shell=
$ helm install coreos/kube-prometheus --name kube-prometheus --namespace=monitoring
```

完成後檢查安裝結果：
```shell=
$ kubectl -n monitoring get po,svc
NAME                                                       READY     STATUS    RESTARTS   AGE
pod/alertmanager-alertmanager-0                            2/2       Running   0          1m
pod/alertmanager-kube-prometheus-0                         2/2       Running   0          31s
pod/grafana-grafana-77cfcdff66-jwxfp                       2/2       Running   0          1m
pod/kube-prometheus-exporter-kube-state-56857b596f-knt8q   1/2       Running   0          21s
pod/kube-prometheus-exporter-kube-state-844bb6f589-n7xfg   1/2       Running   0          31s
pod/kube-prometheus-exporter-node-665kc                    1/1       Running   0          31s
pod/kube-prometheus-exporter-node-bjvbx                    1/1       Running   0          31s
pod/kube-prometheus-exporter-node-j8jf8                    1/1       Running   0          31s
pod/kube-prometheus-exporter-node-pxn8p                    1/1       Running   0          31s
pod/kube-prometheus-exporter-node-vft8b                    1/1       Running   0          31s
pod/kube-prometheus-grafana-57d5b4d79f-lq5cr               1/2       Running   0          31s
pod/prometheus-kube-prometheus-0                           3/3       Running   1          29s
pod/prometheus-operator-d75587d6-qhz4h                     1/1       Running   0          2m
pod/prometheus-prometheus-0                                3/3       Running   1          1m

NAME                                          TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)             AGE
service/alertmanager                          ClusterIP   10.99.170.79     <none>        9093/TCP            1m
service/alertmanager-operated                 ClusterIP   None             <none>        9093/TCP,6783/TCP   1m
service/grafana-grafana                       ClusterIP   10.100.217.27    <none>        80/TCP              1m
service/kube-prometheus                       ClusterIP   10.102.165.173   <none>        9090/TCP            31s
service/kube-prometheus-alertmanager          ClusterIP   10.99.221.122    <none>        9093/TCP            32s
service/kube-prometheus-exporter-kube-state   ClusterIP   10.100.233.129   <none>        80/TCP              32s
service/kube-prometheus-exporter-node         ClusterIP   10.97.183.222    <none>        9100/TCP            32s
service/kube-prometheus-grafana               ClusterIP   10.110.134.52    <none>        80/TCP              32s
service/prometheus                            ClusterIP   10.105.229.141   <none>        9090/TCP            1m
service/prometheus-operated                   ClusterIP   None             <none>        9090/TCP            1m
```
