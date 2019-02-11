---
title: 初探 Knative 基本功能與概念
subtitle: ""
date: 2018-07-27 17:08:54
catalog: true
header-img: /images/kube/bg.png
categories:
- Kubernetes
tags:
- Kubernetes
- Serverless
- Istio
---
![](/images/kube/knative-logo.png)

[Knative](https://github.com/knative) 是基於 Kubernetes 平台建構、部署與管理現代 Serverless 工作負載的開源專案，其目標是要幫助雲端供應商與企業平臺營運商替任何雲端環境的開發者、操作者等提供 Serverless 服務體驗。Knative 採用了 Kubernetes 概念來建構函式與應用程式，並以 Istio 實現了叢集內的網路路由，以及進入服務的外部連接，這讓開發者在部署或執行變得更加簡單。而目前 Knative 元件焦距在解決許多平凡但困難的事情，例如以下：

* 部署一個容器。
* 在 Kubernetes 上編排 Source-to-URL 的工作流程。
* 使用 Blue/Green 部署來路由與管理流量。
* 按需自動擴展與調整工作負載的大小。
* 將運行服務(Running services)綁定到事件生態系統(Eventing ecosystems)。
* 利用原始碼建構應用程式與函式。
* 讓應用程式能夠零停機升級。
* 自動增減應用程式與函式實例。
* 透過 HTTP request 觸發函式的呼叫。
* 為函式、應用程式與容器建立事件。

而 Knative 的設計考慮了不同的工作角色使用情境：

![](/images/kube/knative-audience.png)

然而 Knative 不只使用 Kubernetes 與 Istio 的功能，也自行開發了三個元件以提供更完整的 Serverless 平台。而下節將針對這三個元件進行說明。

## Knative 元件與概念
目前 Knative 提供了以下幾個元件來處理不同的功能需求，本節我們將針對這些元件進行說明。

### Build
[Build](https://github.com/knative/build) 是 Knative 中的自定義資源，並提供了 Build API object 來處理從原始碼(Sources)建構容器的可插拔(Pluggable)模型，這是基於 Google 的容器建構服務(Container Build Service) 而來，這允許開發者定義容器的來源來打包，例如 Git、Registery(ex: Docker hub)，另外也能將 Buildpacks 當作一種建構的插件來使用，這使 Knative 在建構功能上有更靈活的擴展。

{% colorquote info %}
除了 Buildpacks 外，也能夠將 Google Container Builder、Bazel、Kaniko 與 Jib 等等當作建構插件使用。
{% endcolorquote %}

而一個 Knative builds 的主要特性如下：

* 一個`Build`可以包含多個 step，其中每個 step 會指定一個`Builder`。
* 一個`Builder`是一種容器映像檔，可以建立該映像檔來完成任何任務，如流程中的單一 step，或是整個流程本身。
* `Build` 中的 steps 可以推送(push)到一個儲存庫(repository)。
* 一個`BuildTemplate`可用在定義重用的模板。
* 可以定義`Build`中的`source`來將檔案或專案掛載到 Kubernetes Volume(會掛載成`/workspace`)。目前支援：
  * Git 儲存庫
  * Google Cloud Storage
  * 任意的容器映像檔
* 利用 Kubernetes Secrets 結合 ServiceAccount 進行身份認證

{% colorquote info %}
這邊的`step`可以看作是 Kubernetes 的 init-container。
{% endcolorquote %}

以下是一個提供使用者身份認證的 Build 範例，該範例包含多個 step 與 Git repo：
```yml
apiVersion: build.knative.dev/v1alpha1
kind: Build
metadata:
  name: example-build
spec:
  serviceAccountName: build-auth-example
  source:
    git:
      url: https://github.com/example/build-example.git
      revision: master
  steps:
  - name: ubuntu-example
    image: ubuntu
    args: ["ubuntu-build-example", "SECRETS-example.md"]
  steps:
  - image: gcr.io/example-builders/build-example
    args: ['echo', 'hello-example', 'build']
```

### Serving
[Serving](https://github.com/knative/serving) 以 Kubernetes 與 Istio 為基礎，實現了中介軟體原語(Middleware Primitives)來達到自動化從容器到函式執行的整個流程，另外也支援了快速部署容器並進行伸縮的功能，甚至能根據請求來讓容器實例降到 0，而 Serving 也會利用 Istio 在修訂版本之間路由流量，或是將流量傳送到同一個應用程式的多個修訂版本中，除了上述功能外， Serving 也能實現了不停機更新、Bule/Green 部署、部分負載測試，以及程式碼回滾等功能。

![](/images/kube/object_model.png)

從上圖，可以得知 Serving 利用了 Kubernetes CRD 新增一組 API 來定義與控制在 Kubernetes 上的 Serverless 的行為，其分別為以下：

* **Service**：該資源用來自動管理整個工作負載的生命週期，並提供單點控制。它控制了其他物件的建立，以確保應用程式與函式具備每次 Service 更新的 Route、Configuration 與 Revision，而 Service 也可以定義流量路由到最新 Revision 或固定的 Revision。

 ```yml
 apiVersion: serving.knative.dev/v1alpha1
 kind: Service
 metadata:
    name: service-example
 spec:
    runLatest:
      configuration:
        revisionTemplate:
          spec:
            container:
              image: gcr.io/knative-samples/helloworld-go
              env:
              - name: TARGET
                value: "Go Sample v1"   
 ```

* **Route**：該資源將網路端點映射到一個或多個 revision，並且能透過多種方式來管理流量，如部分的流量(fractional traffic)、命名路由(named routes)。

 ```yml
 apiVersion: serving.knative.dev/v1alpha1
 kind: Route
 metadata:
    name: route-example
 spec:
    traffic:
    - configurationName: stock-configuration-example
      percent: 100
 ```

* **Configuration**：該資源維護部屬所需的狀態，它提供了程式碼與組態檔之間的分離，並遵循 Twelve-Factor  App 方法，若修改 Configuration 會建立新 revision。

 ```yml
 apiVersion: serving.knative.dev/v1alpha1
 kind: Configuration
 metadata:
   name: configuration-example
 spec:
   revisionTemplate:
     metadata:
       labels:
         knative.dev/type: container
     spec:
       container:
         image: github.com/knative/docs/serving/samples/rest-api-go
         env:
           - name: RESOURCE
             value: stock
         readinessProbe:
           httpGet:
             path: /
           initialDelaySeconds: 3
           periodSeconds: 3
 ```

* **Revision**：該資源是記錄每個工作負載修改的程式碼與組態的時間點快照，而 Revision 是不可變物件，並且只要它還有用處，就會被長時間保留。

 ```yml
 apiVersion: serving.knative.dev/v1alpha1
 kind: Revision
 metadata:
   labels:
     serving.knative.dev/configuration: helloworld-go
   name: revision-example
   namespace: default
 spec:
   concurrencyModel: Multi
   container:
     env:
     - name: TARGET
       value: Go Sample v1
     image: gcr.io/knative-samples/helloworld-go
   generation: 1
   servingState: Active
 ```

### Eventing
[Eventing](https://github.com/knative/eventing) 提供用於 Consuming 以及 Producing 的事件建構區塊，並遵守著 [CloudEvents](https://github.com/cloudevents) 規範來實現，而該元件目標是對事件進行抽象處理，以讓開發者不需要關注後端相關具體細節，這樣開發者就不需要思考使用哪一套訊息佇列系統。

![](/images/kube/knative-event-arch.png)

而 Knative Eventing 也透過 Kubernetes CRD 定義了一組新資源，這些資源被用在事件的 Producing 與 Consuming 上，而這類資源主要分成以下：

* **Channels**
  * 這些是發布者(Publishers)向其發送訊息的 Pub/Sub Topics，因此 Channel 可視為獲取或放置事件的位置目錄。
  * Bus。Channels 的後端供應者，即支援事件的訊息服務平台，如 Google Cloud PubSub、Apache Kafka 與 NATS 等等。

  ```yml
  apiVersion: channels.knative.dev/v1alpha1
  kind: Bus
  metadata:
    name: kafka
  spec:
    dispatcher:
      args:
      - -logtostderr
      - -stderrthreshold
      - INFO
      env:
      - name: KAFKA_BROKERS
        valueFrom:
          configMapKeyRef:
            key: KAFKA_BROKERS
            name: kafka-bus-config
      image: gcr.io/knative-releases/github.com/knative/eventing/pkg/buses/kafka/dispatcher@sha256:d925663bb965001287b042c8d3ebdf8b4d3f0e7aa2a9e1528ed39dc78978bcdb
      name: dispatcher
  ```

  * 為應用程式與函式指定 Knative Service，並指明 Channel 所要傳遞的具體訊息。為程式與函式的進入位址。

* **Feeds**: 提供一個抽象層來讓外部可以提供資料來源，並將之路由到叢集中。會將事件來源中的單個事件類型附加到某一個行為。
  * EventSource 與 ClusterEventSource 是一個 Kubernetes 資源，被用來描述可能產生的 EventTypes 外部系統。

  ```yml
  apiVersion: feeds.knative.dev/v1alpha1
  kind: EventSource
  metadata:
    name: github
    namespace: default
  spec:
    image: gcr.io/knative-releases/github.com/knative/eventing/pkg/sources/github@sha256:a5f6733797d934cd4ba83cf529f02ee83e42fa06fd0e7a9d868dd684056f5db0
    source: github
    type: github
  ```

  * EventType 與 ClusterEventType 同樣是 Kubernetes 資源，被用來表示不同 EventSource 支援的事件類型。

  ```yml
  apiVersion: feeds.knative.dev/v1alpha1
  kind: EventType
  metadata:
    name: pullrequest
    namespace: default
  spec:
    description: notifications on pullrequests
    eventSource: github
  ```

* **Flows**: 該資源會將事件綁定到 Route(應用程式與函式端點)上，並選擇使用哪種事件路由的 Channel 與 Bus。

 ```yml
 apiVersion: flows.knative.dev/v1alpha1
 kind: Flow
 metadata:
   name: k8s-event-flow
   namespace: default
 spec:
   serviceAccountName: feed-sa
   trigger:
     eventType: dev.knative.k8s.event
     resource: k8sevents/dev.knative.k8s.event
     service: k8sevents
     parameters:
       namespace: default
   action:
     target:
       kind: Route
       apiVersion: serving.knative.dev/v1alpha1
       name: read-k8s-events
 ```

以上是簡單介紹，接下來我們將透過 Minikube 來初步玩玩 Knative 功能。

## 透過 Minikube 初步入門
本節將安裝 Minikube 來建立 Knative 環境，透過完成簡單範例來體驗。

### 事前準備
* 在測試機器安裝 Minikube 二進制執行檔，請至 [Minikube Releases](https://github.com/kubernetes/minikube/releases) 下載。

* 在測試機器下載 [Virtual Box](https://www.virtualbox.org/wiki/Downloads) 來提供給 Minikube 建立虛擬機。

{% colorquote warning %}
* **IMPORTANT**: 測試機器記得開啟 VT-x or AMD-v virtualization.
* 雖然建議用 vbox，但是討厭 Oracle 的人可以改用其他虛擬化工具(ex: kvm, xhyve)，理論上可以動。
{% endcolorquote %}

* 下載 Kubernetes CLI 工具 [kubeclt](https://kubernetes.io/docs/tasks/tools/install-kubectl/)。

### 啟動 Minukube
首天透過 Minikube 來啟動一台 VM 部署單節點 Kubernetes，由於這邊會用到很多系統服務，因此需要開多一點系統資源：
```sh
$ minikube start --memory=8192 --cpus=4 \
  --kubernetes-version=v1.10.5 \
  --extra-config=apiserver.admission-control="LimitRanger,NamespaceExists,NamespaceLifecycle,ResourceQuota,ServiceAccount,DefaultStorageClass,MutatingAdmissionWebhook"
```

完成後，透過 kubectl 檢查：
```sh
$ kubectl get no
NAME       STATUS    ROLES     AGE       VERSION
minikube   Ready     master    1m        v1.10.5
```

### 部署 Knative
由於 Knative 是基於 Istio 所開發，因此需要先部署相關服務，這邊透過 kubectl 來建立：
```sh
$ curl -L https://storage.googleapis.com/knative-releases/serving/latest/istio.yaml \
  | sed 's/LoadBalancer/NodePort/' \
  | kubectl apply -f -

# 設定 inject namespace
$ kubectl label namespace default istio-injection=enabled
```

這邊會需要一點時間下載映像檔，並啟動 Istio 服務，完成後會如下所示：
```sh
$ kubectl -n istio-system get po
NAME                                       READY     STATUS      RESTARTS   AGE
istio-citadel-7bdc7775c7-jn2bw             1/1       Running     0          5m
istio-cleanup-old-ca-msvkn                 0/1       Completed   0          5m
istio-egressgateway-795fc9b47-4nz7j        1/1       Running     0          6m
istio-ingress-84659cf44c-pvqd5             1/1       Running     0          6m
istio-ingressgateway-7d89dbf85f-tgm24      1/1       Running     0          6m
istio-mixer-post-install-lvrjv             0/1       Completed   0          6m
istio-pilot-66f4dd866c-zmbv5               2/2       Running     0          6m
istio-policy-76c8896799-cqmdn              2/2       Running     0          6m
istio-sidecar-injector-645c89bc64-9mdwx    1/1       Running     0          5m
istio-statsd-prom-bridge-949999c4c-qhdgf   1/1       Running     0          6m
istio-telemetry-6554768879-b6vss           2/2       Running     0          6m
```

接著部署 Knative 元件至 Kubernetes 叢集，官方提供了一個`release-lite.yaml`檔案來協助建立輕量的測試環境，因此可以直接透過 kubectl 來建立：
```sh
$ curl -L https://storage.googleapis.com/knative-releases/serving/latest/release-lite.yaml \
  | sed 's/LoadBalancer/NodePort/' \
  | kubectl apply -f -
```

{% colorquote info %}
* 這邊會部署以 Prometheus 組成的 Monitoring 系統，以及 Knative Serving 與 Build。
* 若是其他環境上的 Kubernetes 可以參考 [Knative Install](https://github.com/knative/docs/tree/master/install)。
{% endcolorquote %}

這邊同樣需要一點時間來下載映像檔，並啟動相關服務，一但完成後會如下所示：
```sh
# Monitoring
$ kubectl -n monitoring get po
NAME                                  READY     STATUS    RESTARTS   AGE
grafana-798cf569ff-m8w9c              1/1       Running   0          4m
kube-state-metrics-77597b45f8-mxhxv   4/4       Running   0          1m
node-exporter-8wbxd                   2/2       Running   0          4m
prometheus-system-0                   1/1       Running   0          4m
prometheus-system-1                   1/1       Running   0          4m

# Knative build
$ kubectl -n knative-build get po
NAME                                READY     STATUS    RESTARTS   AGE
build-controller-5cb4f5cb67-bs94k   1/1       Running   0          6m
build-webhook-6b4c65546b-fzffg      1/1       Running   0          6m

# Knative serving
$ kubectl -n knative-serving get po
NAME                          READY     STATUS    RESTARTS   AGE
activator-869d7d76c5-fngdm    2/2       Running   0          7m
autoscaler-65855c89f6-pmzhr   2/2       Running   0          7m
controller-5fbcf79dfb-q8cb8   1/1       Running   0          7m
webhook-c98c7c654-lpnjj       1/1       Running   0          7m
```

到這邊已完成部署 Knative 元件，接下來將透過一些範例來了解 Knative 功能。

### 部署 Knative 應用程式
當上述元件部署完成後，就可以開始建立 Knative 應用程式與函式，這邊將利用簡單 HTTP Server + Slack 來實作一個簡單 Channel 訊息傳送，過程中將會使用到 Build、BuildTemplate 與 Knative Service 等資源。在開始前，先透過 Git 來取得範例專案，這邊主要是使用裡面的 Kubernetes 部署檔案：
```sh
$ git clone https://github.com/kairen/knative-slack-app
$ cd knative-slack-app
```

由於本範例會利用 Kaniko 來建構應用程式的容器映像檔，並將自動將建構好的映像檔上傳至 DockeHub，因此這邊為了確保能夠上傳到自己的 DockerHub，需要建立 Secert 與 Service Account 來提供 Docker ID 與 Passwrod 給 Knative serving 使用：
```sh
$ export DOCKER_ID=$(echo -n "username" | base64)
$ export DOCKER_PWD=$(echo -n "password" | base64)
$ cat deploy/docker-secret.yml | \
  sed "s/BASE64_ENCODED_USERNAME/${DOCKER_ID}/" | \
  sed "s/BASE64_ENCODED_PASSWORD/${DOCKER_PWD}/" | \
  kubectl apply -f -

$ kubectl apply -f deploy/kaniko-sa.yml
```

接著建立一個 Secret 來保存 Slack 的資訊以提供給 Slack App 使用，如 Token：
```sh
$ export SLACK_TOKEN=$(echo -n "slack-token" | base64)
$ export SLACK_CHANNEL_ID=$(echo -n "slack-channel-id" | base64)
$ cat deploy/slack-secret.yml | \
  sed "s/BASE64_ENCODED_SLACK_TOKEN/${SLACK_TOKEN}/" | \
  sed "s/BASE64_ENCODED_SLACK_CHANNEL_ID/${SLACK_CHANNEL_ID}/" | \
  kubectl apply -f -
```

接著建立 Kaniko Build template 來提供給 Knative Service 建構使用：
```sh
$ kubectl apply -f deploy/kaniko-buildtemplate.yml
$ kubectl get buildtemplate
NAME      CREATED AT
kaniko    7s
```

上面完成後，建立 Knative service 與 Istio HTTPS Service Entry 來提供應用程式，以及讓 Pod 能夠存取 Slack HTTPs API：
```sh
$ kubectl apply -f deploy/slack-https-sn.yml
$ kubectl apply -f deploy/slack-app-service.yml
$ kubectl get po -w
NAME                    READY     STATUS     RESTARTS   AGE
slack-app-00001-9htqm   0/1       Init:2/3   0          8s
slack-app-00001-9htqm   0/1       Init:2/3   0         8s
slack-app-00001-9htqm   0/1       PodInitializing   0         3m
slack-app-00001-9htqm   0/1       Completed   0         4m
slack-app-00001-deployment-75f7f8dd8c-tskq8   0/3       Pending   0         0s
slack-app-00001-deployment-75f7f8dd8c-tskq8   0/3       Pending   0         0s
slack-app-00001-deployment-75f7f8dd8c-tskq8   0/3       Init:0/1   0         0s
slack-app-00001-deployment-75f7f8dd8c-tskq8   0/3       PodInitializing   0         7s
slack-app-00001-deployment-75f7f8dd8c-tskq8   2/3       Running   0         33s
```

{% colorquote info %}
這邊第一次執行會比較慢，因為需要下載 knative build 相關映像檔。
{% endcolorquote %}

經過一段時間完成後，透過以下指令來確認服務是否正常：
```sh
$ export IP_ADDRESS=$(minikube ip):$(kubectl get svc knative-ingressgateway -n istio-system   -o 'jsonpath={.spec.ports[?(@.port==80)].nodePort}')
$ export DOMAIN=$(kubectl get services.serving.knative.dev slack-app -o=jsonpath='{.status.domain}')

# 透過 cURL 工具以 Get method 存取
$ curl -X GET -H "Host: ${DOMAIN}" ${IP_ADDRESS}
<h1>Hello slack app for Knative!!</h1>

# 透過 cURL 工具以 Post method 傳送 msg
$ curl -X POST \
  -H 'Content-type: application/json' \
  -H "Host: ${DOMAIN}" \
  --data '{"msg":"Hello, World!"}' \
  ${IP_ADDRESS}

success
```

若成功的話，可以查看 Slack channel 是否有傳送訊息：

![](/images/kube/slack-send-msg.png)

最後由於 Knative Serving 是 Request-driven，因此經過長時間沒有任何 request 時，將會自動縮減至 0 副本，直到再次收到 request 才會再次啟動一個實例，然而 Knative 也將大多資訊以 Prometheus 進行監控，因此我們能透過 Prometheus 來觀察狀態變化。

首先透過 kubectl 取得 Grafana NodePort 資訊：
```sh
$ kubectl -n monitoring get svc
NAME                          TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)               AGE
...
grafana                       NodePort    10.96.197.116   <none>        30802:30326/TCP       1h
prometheus-system-np          NodePort    10.99.64.228    <none>        8080:32628/TCP        1h
...
```

透過瀏覽器開啟 http://minikube_ip:port 來查看。

![](https://i.imgur.com/IBR4rMO.png)

另外也可以查看 HTTP request 狀態。

![](https://i.imgur.com/TIlIMhX.png)

由於 Knative 是蠻大的系統，這邊先暫時使用基本 Knative 的 Build 與 Serving，而 Eventing 將會在之後補充範例。
