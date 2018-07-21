---
title: 以 ExternalDNS 自動同步 Kubernetes Ingress 與 Service DNS 資源紀錄
date: 2018-7-19 17:08:54
catalog: true
header-img: /images/kube/bg.png
categories:
- Kubernetes
tags:
- Kubernetes
- CoreDNS
---
本篇說明如何透過 [CoreDNS](https://github.com/coredns/coredns) 自建一套 DNS 服務，並利用 [Kubernetes ExternalDNS](https://github.com/kubernetes-incubator/external-dns) 同步 Kubernetes 的 Ingress 與 Service API object 中的域名(Domain Name)來產生資源紀錄(Record Resources)，讓使用者能夠透過自建 DNS 服務來導向到 Kubernetes 上的應用服務。

<!--more-->

## 使用元件功能介紹

* **CoreDNS**：用來提供使用者的 DNS 解析以處理服務導向，並利用 Etcd 插件來儲存與查詢 DNS 資源紀錄(Record resources)。CoreDNS 是由 CNCF 維護的開源 DNS 專案，該專案前身是 SkyDNS，其採用了 [Caddy](https://github.com/mholt/caddy) 的一部分來開發伺服器框架，使其能夠建構一套快速靈活的 DNS，而 CoreDNS 每個功能都可以被實作成一個插件的中介軟體，如 Log、Cache 等功能，甚至能夠將源紀錄儲存至 Redis、Etcd 中。另外 CoreDNS 目前也被 Kubernetes 作為一個內部服務查詢的核心元件，並慢慢取代 KubeDNS 來提供使用。

{% colorquote info %}
由於市面上大多以 Bind9 作為 DNS，但是 Bind9 並不支援插件與 REST API 功能，雖然效能高又穩定，但是在一些場景並不靈活。
{% endcolorquote %}

* **Etcd**：用來儲存 CoreDNS 資源紀錄，並提供給整合的元件查詢與儲存使用。Etcd 是一套分散式鍵值(Key/Value)儲存系統，其功能類似 ZooKeeper，而 Etcd 在一致性演算法採用了 Raft 來處理多節點高可靠性問題，Etcd 好處是支援了 REST API、JSON 格式、SSL 與高效能等，而目前 Etcd  被應用在 Kubernetes 與 Cloud Foundry 等專案中。
* **ExternalDNS**：用於定期同步 Kubernetes Service 與 Ingress 資源，並依據 Kubernetes 資源內容產生 DNS 資源紀錄來設定 CoreDNS，架構中採用 Etcd 作為兩者溝通中介，一旦有資源紀錄產生就儲存至 Etcd 中，以提供給 CoreDNS 作為資源紀錄來確保服務辨識導向。ExternalDNS 是 Kubernetes 社區的專案，目前被用於同步 Kubernetes 自動設定公有雲 DNS 服務的資源紀錄。

* **Ingress Controller**：提供 Kubernetes Service 能夠以 Domain Name 方式提供外部的存取。Ingress Controller 會監聽 Kubernetes API Server 的 Ingress 與 Service 抽象資源，並依據對應資訊產生組態檔來設定到一個以 NGINX 為引擎的後端，當使用者存取對應服務時，會透過 NGINX 後端進入，這時會依據設定檔的 Domain Name 來轉送給對應 Kubernetes Service。

{% colorquote info %}
Ingress Controller 除了社區提供的專案外，還可以使用 [Traefik](https://docs.traefik.io/user-guide/kubernetes/)、[Kong](https://github.com/Kong/kubernetes-ingress-controller) 等專案。
{% endcolorquote %}

* **Kubernetes API Server**：ExternalDNS 會定期抓取來至 API Server 的 Ingress 與 Service 抽象資源，並依據資源內容產生資源紀錄。

## 運作流程
本節說明該架構運作流程，首先當使用者建立了一個 Kubernetes Service 或 Ingress(實作以同步 Ingress 為主)時，會透過與 API Server 溝通建立至 Kubernetes 叢集中，一旦 Service 或 Ingress 建立完成，並正確分配 Service external IP 或是 Ingress address 後，`ExternalDNS` 會在同步期間抓取所有 Namespace(或指定)中的 Service 與 Ingress 資源，並從 Service 的`metadata.annotations`取出`external-dns.alpha.kubernetes.io/hostname`鍵的值，以及從 Ingress 中的`spec.rules`取出 host 值來產生 DNS 資源紀錄(如 A record)，當完成產生資源紀錄後，再透過 Etcd 儲存該紀錄來讓 CoreDNS 在收到查詢請求時，能夠依據 Etcd 的紀錄來辨識導向。

![](https://i.imgur.com/b4QPkr9.png)

拆解不同流程步驟如下：

1. 使用者建立一個帶有 annotations 的 Service 或是 Ingress。

```yaml=
apiVersion: v1
kind: Service
metadata:
  name: nginx
  annotations:
    external-dns.alpha.kubernetes.io/hostname: nginx.k8s.local # 將被自動註冊的 domain name.
spec:
  type: NodePort
  selector:
    app: nginx
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
---
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: nginx-ingress
spec:
  rules:
  - host: nginx.k8s.local # 將被自動註冊的 domain name.
    http:
      paths:
      - backend:
          serviceName: nginx
          servicePort: 80
```
> 該範例中，若使用 Ingress 的話則不需要在 Service 塞入`external-dns.alpha.kubernetes.io/hostname`，且不需要使用 NodePort 與 LoadBalancer。

2. ExternalDNS 接收到 Service 與 Ingress 抽象資源，取出將被用來註冊 Domain Name 的資訊，並依據上述資訊產生 DNS 資源紀錄(Record resources)，然後儲存到 Etcd。
3. 當使用者存取 `nginx.k8s.local` 時，將對 CoreDNS 提供的 DNS 伺服器發送查詢請求，這時 CoreDNS 會到 Etcd 找尋資源紀錄來進行辨識重導向功能，若找到資源紀錄回覆解析結果給使用者。
4. 這時使用者正確地被導向位址。其中若使用 Service 則要額外輸入對應 Port，用 Ingress 則能夠透過 DN 存取到服務，這是由於 Ingress controller  提供了一個 NGINX Proxy 後端來轉至對應的內部服務。

## 測試環境部署
本節將說明如何透過簡單測試環境來實作上述功能。

### 節點資訊
測試環境將需要一套 Kubernetes 叢集，作業系統採用`Ubuntu 16.04 Server`，測試環境為實體機器：

| IP Address    | Role   | vCPU | RAM |
|---------------|--------|------|-----|
| 172.22.132.10 | k8s-m1 | 8    | 16G |
| 172.22.132.11 | k8s-n1 | 8    | 16G |
| 172.22.132.12 | k8s-n2 | 8    | 16G |
| 172.22.132.13 | k8s-g1 | 8    | 16G |
| 172.22.132.14 | k8s-g2 | 8    | 16G |

> 這邊`m`為 k8s master，`n`為 k8s node。

### 事前準備
開始安裝前需要確保以下條件已達成：

* 所有節點以 kubeadm 部署成 Kubernetes v1.10+ 叢集。請參考 [用 kubeadm 部署 Kubernetes 叢集](https://kairen.github.io/2016/09/29/kubernetes/deploy/kubeadm/)。

### 部署 DNS 系統
首先透過 Git 取得部署用檔案：
```shell=
$ git clone https://github.com/kairen/k8s-external-coredns.git
$ cd k8s-external-coredns
```

執行以下指令修改一些部署檔案：
```shell=
$ sudo sed -i "s/172.22.132.10/${MASTER_IP}/g" ingress-controller/ingress-controller.yaml
$ sudo sed -i "s/172.22.132.10/${MASTER_IP}/g" dns/coredns/coredns-svc-udp.yml
$ sudo sed -i "s/172.22.132.10/${MASTER_IP}/g" dns/coredns/coredns-svc-tcp.yml
$ sudo sed -i "s/k8s.local/${DOMAIN_NAME}/g" dns/coredns/coredns-cm.yml
```
> 這邊因為方便在我環境測試，所以檔案沒改 IP 跟 Domain Name。

完成後開始部署至 Kubernetes 中，首先部署 Ingress Controller：
```shell=
$ kubectl create -f ingress-controller/
namespace "ingress-nginx" created
deployment.extensions "default-http-backend" created
service "default-http-backend" created
configmap "nginx-configuration" created
configmap "tcp-services" created
configmap "udp-services" created
serviceaccount "nginx-ingress-serviceaccount" created
clusterrole.rbac.authorization.k8s.io "nginx-ingress-clusterrole" created
role.rbac.authorization.k8s.io "nginx-ingress-role" created
rolebinding.rbac.authorization.k8s.io "nginx-ingress-role-nisa-binding" created
clusterrolebinding.rbac.authorization.k8s.io "nginx-ingress-clusterrole-nisa-binding" created
service "ingress-nginx" created
deployment.extensions "nginx-ingress-controller" created

$ kubectl -n ingress-nginx get svc,po
NAME                           TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)        AGE
service/default-http-backend   ClusterIP      10.108.17.210   <none>          80/TCP         22s
service/ingress-nginx          LoadBalancer   10.100.149.79   172.22.132.10   80:30383/TCP   22s

NAME                                            READY     STATUS    RESTARTS   AGE
pod/default-http-backend-5c6d95c48-5qm4g        1/1       Running   0          22s
pod/nginx-ingress-controller-6c9fcdf8d9-fmnlf   1/1       Running   0          22s
```

確認沒問題後，透過瀏覽器開啟`External-IP:80`來存取頁面。結果如下：

![](https://i.imgur.com/wThG3PC.png)

接著部署 CoreDNS 服務：
```shell=
$ kubectl create -f dns/
namespace "dns" created

$ kubectl create -f dns/coredns/
configmap "coredns" created
deployment.extensions "coredns" created
service "coredns-tcp" created
service "coredns-udp" created
deployment.extensions "coredns-etcd" created
service "coredns-etcd" created

$ kubectl -n dns get po,svc
NAME                                READY     STATUS    RESTARTS   AGE
pod/coredns-776f94cf7d-rntxg        1/1       Running   0          16s
pod/coredns-etcd-847b657579-bnmr5   1/1       Running   0          15s

NAME                   TYPE           CLUSTER-IP       EXTERNAL-IP     PORT(S)                       AGE
service/coredns-etcd   ClusterIP      10.107.144.189   <none>          2379/TCP,2380/TCP             15s
service/coredns-tcp    LoadBalancer   10.96.34.152     172.22.132.10   53:30050/TCP,9153:32082/TCP   16s
service/coredns-udp    LoadBalancer   10.97.40.197     172.22.132.10   53:30477/UDP                  16s
```

確認沒問題後，在使用的系統設定 DNS 伺服器，如下：

![](https://i.imgur.com/p6vkPPw.png)

透過 dig 測試 SOA 結果：
```shell=
$ dig @172.22.132.10 SOA k8s.local +noall +answer

; <<>> DiG 9.10.6 <<>> @172.22.132.10 SOA k8s.local +noall +answer
; (1 server found)
;; global options: +cmd
k8s.local.		300	IN	SOA	ns.dns.k8s.local. hostmaster.k8s.local. 1530255393 7200 1800 86400 30
```

接著部署 ExternalDNS 來提供自動註冊 Kubernetes record 至 CoreDNS：
```shell=
$ kubectl create -f dns/external-dns/
serviceaccount "external-dns" created
clusterrole.rbac.authorization.k8s.io "external-dns" created
clusterrolebinding.rbac.authorization.k8s.io "external-dns-viewer" created
deployment.apps "external-dns" created

$ kubectl -n dns get po -l k8s-app=external-dns
NAME                           READY     STATUS    RESTARTS   AGE
external-dns-94647696b-m494c   1/1       Running   0          38s
```

檢查 ExternalDNS Pod 是否正確：
```shell=
$ kubectl -n dns logs -f external-dns-94647696b-m494c
...
time="2018-06-29T06:58:35Z" level=info msg="Connected to cluster at https://10.96.0.1:443"
time="2018-06-29T06:58:35Z" level=debug msg="No endpoints could be generated from service default/kubernetes"
time="2018-06-29T06:58:35Z" level=debug msg="No endpoints could be generated from service dns/coredns-etcd"
...
```

## 服務測試
當部署完成後，這時就能夠透過建立一些簡單範例來測試功能是否正確。這邊透過建立一個 cheese 範例來解析三個不同的網頁內容：

* stilton.k8s.local 將導到`斯蒂爾頓`起司頁面。
* cheddar.k8s.local 將導到`切達`起司頁面。
* wensleydale.k8s.local 將導到`文斯勒德起司`起司頁面。

開始前，先用 dig 來測試使用的 DN 是否能被解析：
```shell=
$ dig @172.22.132.10 A stilton.k8s.local +noall +answer

; <<>> DiG 9.10.6 <<>> @172.22.132.10 A stilton.k8s.local +noall +answer
; (1 server found)
;; global options: +cmd
```
> 可以發現沒有任何 A Record 回傳。

執行下述指令來完成部署：
```shell=
$ kubectl create -f apps/cheese/
deployment.extensions "stilton" created
deployment.extensions "cheddar" created
deployment.extensions "wensleydale" created
ingress.extensions "cheese" created
service "stilton" created
service "cheddar" created
service "wensleydale" created

$ kubectl get po,svc,ing
NAME                               READY     STATUS    RESTARTS   AGE
pod/cheddar-55cdc7bcc4-926tn       1/1       Running   0          26s
pod/stilton-5948f8889d-kmj2m       1/1       Running   0          26s
pod/wensleydale-788869b958-z2kzs   1/1       Running   0          26s

NAME                  TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)   AGE
service/cheddar       ClusterIP   10.109.22.242    <none>        80/TCP    26s
service/kubernetes    ClusterIP   10.96.0.1        <none>        443/TCP   9d
service/stilton       ClusterIP   10.102.175.194   <none>        80/TCP    26s
service/wensleydale   ClusterIP   10.103.30.255    <none>        80/TCP    25s

NAME                        HOSTS                                                       ADDRESS         PORTS     AGE
ingress.extensions/cheese   stilton.k8s.local,cheddar.k8s.local,wensleydale.k8s.local   172.22.132.10   80        26s
```

確認完成部署後，透過 nslookup 來確認能夠解析 Domain Name：
```shell=
$ dig @172.22.132.10 A stilton.k8s.local +noall +answer

; <<>> DiG 9.10.6 <<>> @172.22.132.10 A stilton.k8s.local +noall +answer
; (1 server found)
;; global options: +cmd
stilton.k8s.local.	300	IN	A	172.22.132.10
```

現在存取`stilton.k8s.local`、`cheddar.k8s.local`與`wensleydale.k8s.local`來查看差異吧。

![](https://i.imgur.com/0nfDKev.jpg)

![](https://i.imgur.com/tJmcBZL.jpg)
