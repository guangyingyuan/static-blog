---
title: Kuberentes Helm 介紹
date: 2017-03-25 17:08:54
catalog: true
categories:
- Kubernetes
tags:
- Helm
- Docker
- Kubernetes
---
[Helm](https://github.com/kubernetes/helm) 是 Kubernetes Chart 的管理工具，Kubernetes Chart 是一套預先組態的 Kubernetes 資源套件。使用 Helm 有以下幾個好處：
* 查詢與使用熱門的 [Kubernetes Chart](https://github.com/kubernetes/charts) 軟體套件。
* 以 Kuberntes Chart 來分享自己的應用程式。
* 可利用 Chart 來重複建立應用程式。
* 智能地管理 Kubernetes manifest 檔案。
* 管理釋出的 Helm 版本。

<!--more-->

## 概念
Helm 有三個觀念需要我們去了解，分別為 Chart、Release 與 Repository，其細節如下：
* **Chart**：主要定義要被執行的應用程式中，所需要的工具、資源、服務等資訊，有點類似 Homebrew 的 Formula 或是 APT 的 dpkg 檔案。
* **Release**：一個被執行於 Kubernetes 的 Chart 實例。Chart 能夠在一個叢集中擁有多個 Release，例如 MySQL Chart，可以在叢集建立基於該 Chart 的兩個資料庫實例，其中每個 Release 都會有獨立的名稱。
* **Repository**：主要用來存放 Chart 的倉庫，如 [KubeApps](https://kubeapps.com/)。

可以理解 Helm 主要目標就是從 Chart Repository 中，查找部署者需要的應用程式 Chart，然後以 Release 形式來部署到 Kubernetes 中進行管理。

## Helm 系統元件
Helm 主要分為兩種元件，Helm Client 與 Tiller Server，兩者功能如下：
* **Helm Client**：一個安裝 Helm CLI 的機器，該機器透過 gRPC 連接 Tiller Server 來對 Repository、Chart 與 Release 等進行管理與操作，如建立、刪除與升級等操作，細節可以查看 [Helm Documentation](https://github.com/kubernetes/helm/blob/master/docs/index.md)。
* **Tiller Server**：主要負責接收來至 Client 的指令，並透過 kube-apiserver 與 Kubernetes 叢集做溝通，根據 Chart 定義的內容，來產生與管理各種對應 API 物件的 Kubernetes 部署檔案(又稱為 `Release`)。

兩者溝通架構圖如下所示：
![](/images/kube/helm-peer.png)

## 事前準備
安裝前需要確認環境滿足以下幾膽：
* 已部署 Kubernetes 叢集。
* 操作端安裝 kubectl 工具。
* 操作端可以透過 kubectl 工具管理到 Kubernetes（可用的 kubectl config）。

## 安裝 Helm
Helm 有許多種安裝方式，這邊個人比較喜歡用 binary 檔案來進行安裝：
```sh
$ wget -qO- https://kubernetes-helm.storage.googleapis.com/helm-v2.8.1-linux-amd64.tar.gz | tar -zx
$ sudo mv linux-amd64/helm /usr/local/bin/
$ helm version
```
> OS X 為下載 `helm-v2.4.1-darwin-amd64.tar.gz`。

## 初始化 Helm
在開始使用 Helm 之前，我們需要建置 Tiller Server 來對 Kubernetes 的管理，而 Helm CLI 內建也提供了快速初始化指令，如下：
```sh
$ kubectl -n kube-system create sa tiller
$ kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller
$ helm init --service-account tiller
$HELM_HOME has been configured at /root/.helm.

Tiller (the helm server side component) has been installed into your Kubernetes Cluster.
Happy Helming!
```
> 若之前只用舊版想要更新可以透過以下指令`helm init --upgrade`來達到效果。

完成後，就可以透過 kubectl 來查看 Tiller Server 是否被建立：
```sh
$ kubectl get po,svc -n kube-system -l app=helm
NAME                                READY     STATUS    RESTARTS   AGE
po/tiller-deploy-1651596238-5lsdw   1/1       Running   0          3m

NAME                CLUSTER-IP        EXTERNAL-IP   PORT(S)     AGE
svc/tiller-deploy   192.162.204.144   <none>        44134/TCP   3m
```

接著透過 helm ctl 來查看資訊：
```sh
$ export KUBECONFIG=/etc/kubernetes/admin.conf
$ export HELM_HOST=$(kubectl describe svc/tiller-deploy -n kube-system | awk '/Endpoints/{print $2}')

# wait for a few minutes
$ helm version
Client: &version.Version{SemVer:"v2.8.1", GitCommit:"6af75a8fd72e2aa18a2b278cfe5c7a1c5feca7f2", GitTreeState:"clean"}
Server: &version.Version{SemVer:"v2.8.1", GitCommit:"6af75a8fd72e2aa18a2b278cfe5c7a1c5feca7f2", GitTreeState:"clean"}
```

## 部署 Chart Release 實例
當完成初始化後，就可以透過 helm ctl 來管理與部署 Chart Release，我們可以到 [KubeApps](https://kubeapps.com/) 查找想要部署的 Chart，如以下快速部屬 Jenkins　範例，首先先透過搜尋來查看目前應用程式版本：
```sh
$ helm search jenkins
NAME          	VERSION	DESCRIPTION
stable/jenkins	0.6.3  	Open source continuous integration server. It s...
```

接著透過`inspect`指令查看該 Chart 的參數資訊：
```sh
$ helm inspect stable/jenkins
...
Persistence:
  Enabled: true
```
> 從中我們會發現需要建立一個 PVC 來提供持久性儲存。

因此需要建立一個 PVC 提供給 Jenkins Chart 來儲存使用，這邊我們自己手動建立`jenkins-pv-pvc.yml`檔案：
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: jenkins-pv
  labels:
    app: jenkins
spec:
  capacity:
    storage: 10Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Recycle
  nfs:
    path: /var/nfs/jenkins
    server: 172.20.3.91

---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: jenkins-pvc
  labels:
    app: jenkins
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
```

接著透過 kubectl 來建立：
```sh
$ kubectl create -f jenkins-pv-pvc.yml
persistentvolumeclaim "jenkins-pvc" created
persistentvolume "jenkins-pv" created

$ kubectl get pv,pvc
NAME            CAPACITY   ACCESSMODES   RECLAIMPOLICY   STATUS    CLAIM                 STORAGECLASS   REASON    AGE
pv/jenkins-pv   10Gi       RWO           Recycle         Bound     default/jenkins-pvc                            20s

NAME              STATUS    VOLUME       CAPACITY   ACCESSMODES   STORAGECLASS   AGE
pvc/jenkins-pvc   Bound     jenkins-pv   10Gi       RWO                          20s
```

當 PVC 建立完成後，就可以開始透過 Helm 來建立 Jenkins Release：
```sh
$ export PVC_NAME=$(kubectl get pvc -l app=jenkins --output=template --template="{{with index .items 0}}{{.metadata.name}}{{end}}")
$ helm install --name demo --set Persistence.ExistingClaim=${PVC_NAME} stable/jenkins
NAME:   demo
LAST DEPLOYED: Thu May 25 17:53:50 2017
NAMESPACE: default
STATUS: DEPLOYED

RESOURCES:
==> v1beta1/Deployment
NAME          DESIRED  CURRENT  UP-TO-DATE  AVAILABLE  AGE
demo-jenkins  1        1        1           0          1s

==> v1/Secret
NAME          TYPE    DATA  AGE
demo-jenkins  Opaque  2     1s

==> v1/ConfigMap
NAME                DATA  AGE
demo-jenkins-tests  1     1s
demo-jenkins        3     1s

==> v1/Service
NAME          CLUSTER-IP       EXTERNAL-IP  PORT(S)                         AGE
demo-jenkins  192.169.143.140  <pending>    8080:30152/TCP,50000:31806/TCP  1s
...
```
> P.S. `install` 指令可以安裝來至`Chart repository`、`壓縮檔 Chart`、`一個 Chart 目錄`與`Chart URL`。
> 這邊 install 可以額外透過以下兩種方式來覆寫參數，在這之前可以先透過`helm inspect values <chart>`來取得使用的變數。
* **--values**：指定一個 YAML 檔案來覆寫設定。
>```sh
$ echo -e 'Master:\n  AdminPassword: r00tme' > config.yaml
$ helm install -f config.yaml stable/jenkins
```
> * **--sets**：指定一對 Key/value 指令來覆寫。
> ```sh
$ helm install --set Master.AdminPassword=r00tme stable/jenkins
```

完成後就可以透過 helm 與 kubectl 來查看建立狀態：
```sh
$ helm ls
NAME	REVISION	UPDATED                 	STATUS  	CHART        	NAMESPACE
demo	1       	Thu May 25 17:53:50 2017	DEPLOYED	jenkins-0.6.3	default

$ kubectl get po,svc
NAME                               READY     STATUS    RESTARTS   AGE
po/demo-jenkins-3139496662-c0lzk   1/1       Running   0          1m

NAME               CLUSTER-IP        EXTERNAL-IP   PORT(S)                          AGE
svc/demo-jenkins   192.169.143.140   <pending>     8080:30152/TCP,50000:31806/TCP   1m
```

由於預設只使用 LoadBalancerSourceRanges 來定義存取策略，但沒有指定任何外部 IP，因此要手動加入以下內容：
```sh
$ kubectl edit svc demo-jenkins

spec:
  externalIPs:
  - 172.20.3.90
```

完成後再次查看 Service 資訊：
```sh
$ kubectl get svc
NAME           CLUSTER-IP        EXTERNAL-IP    PORT(S)                          AGE
demo-jenkins   192.169.143.140   ,172.20.3.90   8080:30152/TCP,50000:31806/TCP   10m
```
> 這時候就可以透過 http://172.20.3.90:8080 連進去 Jenkins 了，其預設帳號為 `admin`。

透過以下指令來取得 Jenkins admin 密碼：
```sh
$ printf $(kubectl get secret --namespace default demo-jenkins -o jsonpath="{.data.jenkins-admin-password}" | base64 --decode);echo
buQ1ik2Q7x
```
> 該 Chart 會產生亂數密碼存放到 secret 中。

![](/images/kube/helm-jenkins.png)

最後我們也可以透過`upgrade`指令來更新已經 Release 的 Chart：
```sh
$ helm upgrade --set Master.AdminPassword=r00tme --set Persistence.ExistingClaim=jenkins-pvc demo stable/jenkins
Release "demo" has been upgraded. Happy Helming!

$ helm get values demo
Master:
  AdminPassword: r00tme
Persistence:
  ExistingClaim: jenkins-pvc

$ helm ls
NAME    REVISION        UPDATED                         STATUS          CHART           NAMESPACE
demo    2               Tue May 30 21:18:43 2017        DEPLOYED        jenkins-0.6.3   default
```
> 這邊會看到`REVISION`會 +1，這可以用來做 rollback 的版本號使用。

## 刪除 Release
Helm 除了基本的建立功能外，其還包含了整個 Release 的生命週期管理功能，如我們不需要該 Release 時，就可以透過以下方式刪除：
```sh
$ helm del demo
$ helm status demo | grep STATUS
STATUS: DELETED
```

當刪除後，該 Release 並沒有真的被刪除，我們可以透過 helm ls 來查看被刪除的 Release：
```sh
$ helm ls --all
NAME    REVISION        UPDATED                         STATUS  CHART           NAMESPACE
demo    2               Tue May 30 21:18:43 2017        DELETED jenkins-0.6.3   default
```
> 當執行 `helm ls` 指令為加入 `--all` 時，表示只列出`DEPLOYED`狀態的 Release。

而當 Release 處於 `DELETED` 狀態時，我們可以進行一些操作，如 Roll back 或完全刪除 Release：
```sh
$ helm rollback demo 1
Rollback was a success! Happy Helming!

$ printf $(kubectl get secret --namespace default demo-jenkins -o jsonpath="{.data.jenkins-admin-password}" | base64 --decode);echo
BIsLlQTN9l

$ helm del demo --purge
release "demo" deleted

# 這時執行以下指令就不會再看到已刪除的 Release.
$ helm ls --all
```

## 建立簡單 Chart 結構
Helm 提供了 create 指令來建立一個 Chart 基本結構：
```sh
$ helm create example
$ tree example/
example/
├── charts
├── Chart.yaml
├── templates
│   ├── deployment.yaml
│   ├── _helpers.tpl
│   ├── ingress.yaml
│   ├── NOTES.txt
│   └── service.yaml
└── values.yaml
```

當我們設定完 Chart 後，就可以透過 helm 指令來打包：
```sh
$ helm package example/
example-0.1.0.tgz
```

最後可以用 helm 來安裝：
```sh
$ helm install ./example-0.1.0.tgz
```

## 自己建立 Repository
Helm 指令除了可以建立 Chart 基本結構外，很幸運的也提供了建立 Helm Repository 的功能，建立方式如下：
```sh
$ helm serve --repo-path example-0.1.0.tgz
$ helm repo add example http://repo-url
```
> 另外 helm repo 也可以加入來至於 Github 與 HTTP 伺服器的網址來提供服務。
