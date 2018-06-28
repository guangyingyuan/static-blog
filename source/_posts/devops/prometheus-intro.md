---
title: Prometheus 介紹與基礎入門
layout: default
comments: true
date: 2018-06-10 12:23:01
categories:
- DevOps
tags:
- DevOps
- Monitoring
- CNCF
- Kubernetes
---
Prometheus 是一套開放式原始碼的`系統監控警報框架`與`TSDB(Time Series Database)`，該專案是由 SoundCloud 的工程師(前 Google 工程師)建立，Prometheus 啟發於 Google 的 Borgmon 監控系統。目前 Prometheus 已貢獻到 CNCF 成為孵化專案(2016-)，其受歡迎程度僅次於 Kubernetes。

<!--more-->

Prometheus 具備了以下特性：

* 多維度資料模型
	* 時間序列資料透過 Metric 名稱與鍵值(Key-value)來區分。
	* 所有 Metrics 可以設定任意的多維標籤。
	* 資料模型彈性度高，不需要刻意設定為以特定符號(ex: ,)分割。
	* 可對資料模型進行聚合、切割與切片操作。
	* 支援雙精度浮點數類型，標籤可以設定成 Unicode。
* 靈活的查詢語言(PromQL)，如可進行加減乘除等。
* 不依賴分散式儲存，因為 Prometheus Server 是一個二進制檔，可在單個服務節點自主運行。
* 基於 HTTP 的 Pull 方式收集時序資料。
* 可以透過 Push Gateway 進行資料推送。
* 支援多種視覺化儀表板呈現，如 Grafana。
* 能透過服務發現(Service discovery)或靜態組態去獲取監控的 Targets。

## Prometheus 架構

![](https://i.imgur.com/iJKoxdD.png)

Prometheus 生態圈中是由多個元件組成，其中有些是選擇性的元件：

* **Prometheus Server**：收集與儲存時間序列資料，並提供 PromQL 查詢語言支援。
* **Client Library**：客戶端函式庫，提供語言開發來開發產生 Metrics 並曝露 Prometheus Server。當 Prometheus Server 來 Pull 時，直接返回即時狀態的 Metrics。
* **Pushgateway**：主要用於臨時性 Job 推送。這類 Job 存在期間較短，有可能 Prometheus 來 Pull 時就消失，因此透過一個閘道來推送。適合用於服務層面的 Metrics。
* **Exporter**：用來曝露已有第三方服務的 Metrics 給 Prometheus Server，即以 Client Library 開發的 HTTP server。
* **AlertManager**：接收來至 Prometheus Server 的 Alert event，並依據定義的 Notification 組態發送警報，ex: E-mail、Pagerduty、OpenGenie 與 Webhook 等等。


## Prometheus 運作流程

1. Prometheus Server 定期從組態好的 Jobs 或者 Exporters 中拉取 Metrics，或者接收來自 Pushgateway 發送的 Metrics，又或者從其他的 Prometheus Server 中拉取 Metrics。
2. Prometheus Server 在 Local 儲存收集到的 Metrics，並運行已定義好的 alert.rules，然後紀錄新時間序列或者像 AlertManager 發送警報。
3. AlertManager 根據組態檔案來對接受到的 Alert event 進行處理，然後發送警報。
4. 在視覺化介面呈現採集資料。

Prometheus Server 拉取 Exporter 資料，然後透過 PromQL 語法進行查詢，再將資料給 Web UI or Dashboard。
![](https://i.imgur.com/QkwEVge.png)

Prometheus Server 觸發 Alert Definition 定義的事件，並發送給 AelertManager。
![](https://i.imgur.com/6V3RJOh.png)

AlertManager 依據設定發送警報給 E-mail、Slack 等等。
![](https://i.imgur.com/mB789G2.png)

## Prometheus 資料模型與 Metric 類型
本節將介紹 Prometheus 的資料模型與 Metrics 類型。

### 資料模型
Prometheus 儲存的資料為時間序列，主要以 Metrics name 以及一系列的唯一標籤(key-value)組成，不同標籤表示不同時間序列。模型資訊如下：

* **Metrics Name**：該名稱通常用來表示 Metric 功能，例如 `http_requests_total`，即表示 HTTP 請求的總數。而 Metrics Name 是以 ASCII 字元、數字、英文、底線與冒號組成，並且要滿足`[a-zA-Z_:][a-zA-Z0-9_:]*` 正規表示法。
* **標籤**：用來識別同一個時間序列不同維度。如 `http_request_total{method="Get"}`表示所有 HTTP 的 Get Request 數量，因此當 `method="Post"` 時又是另一個新的 Metric。標籤也需要滿足`[a-zA-Z_:][a-zA-Z0-9_:]*` 正規表示法。
* **樣本**：實際的時間序列，每個序列包含一個 float64 值與一個毫秒的時間戳。
* **格式**：一般為`<metric name>{<label name>=<label value>,...}`，例如：`http_requests_total{method="POST",endpoint="/api/tracks"}`。

### Metrics 類型
Prometheus Client 函式庫支援了四種主要 Metric 類型：

* **Counter**: 可被累加的 Metric，比如一個 HTTP Get 錯誤的出現次數。
* **Gauge**: 屬於瞬時、與時間無關的任意更動 Metric，如記憶體使用率。
* **Histogram**: 主要使用在表示一段時間範圍內的資料採樣。
* **Summary**： 類似 Histogram，用來表示一端時間範圍內的資料採樣總結。

## Job 與 Instance
Prometheus 中會將任意獨立資料來源(Target)稱為 Instance。而包含多個相同 Instance 的集合稱為 Job。如以下範例：
```yml
- job: api-server
    - instance 1: 1.2.3.4:5670
    - instance 2: 1.2.3.4:5671
    - instance 3: 5.6.7.8:5670
    - instance 4: 5.6.7.8:5671
```

* **Instance**: 被抓取目標 URL 的`<host>:<port>`部分。
* **Job**: 一個同類型的 Instances 集合。(主要確保可靠性與擴展性)

## Prometheus 簡單部署與使用
Prometheus 官方提供了已建構完成的二進制執行檔可以下載，只需要至 [Download](https://prometheus.io/download/) 頁面下載即可。首先下載符合作業系統的檔案，這邊以 Linux 為例：
```sh
$ wget https://github.com/prometheus/prometheus/releases/download/v2.3.0/prometheus-2.3.0.linux-amd64.tar.gz
$ tar xvfz prometheus-*.tar.gz
$ tree prometheus-2.3.0.linux-amd64
├── console_libraries # Web console templates
│   ├── menu.lib
│   └── prom.lib
├── consoles # Web console templates
│   ├── index.html.example
│   ├── node-cpu.html
│   ├── node-disk.html
│   ├── node.html
│   ├── node-overview.html
│   ├── prometheus.html
│   └── prometheus-overview.html
├── LICENSE
├── NOTICE
├── prometheus     # Prometheus 執行檔
├── prometheus.yml # Prometheus 設定檔
└── promtool       # 2.x+ 版本用來將一些 rules 格式轉成 YAML 用。
```

解壓縮完成後，編輯`prometheus.yml`檔案來調整設定：
```yml
global:
  scrape_interval: 15s # 設定預設 scrape 的拉取間隔時間
  external_labels: # 外通溝通時標示在 time series 或 Alert 的 Labels。
    monitor: 'codelab-monitor'

scrape_configs: # 設定 scrape jobs
  - job_name: 'prometheus'
    scrape_interval: 5s # 若設定間隔時間，將會覆蓋 global 的預設時間。
    static_configs:
      - targets: ['localhost:9090']
```

完成後，直接執行 prometheus 檔案來啟動伺服器：
```sh
$ ./prometheus --config.file=prometheus.yml --storage.tsdb.path /tmp/data
...
level=info ts=2018-06-19T08:46:37.42756438Z caller=main.go:500 msg="Server is ready to receive web requests."
```
> `--storage.tsdb.path` 預設會直接存放在`./data`底下。

啟動後就可以瀏覽 `:9090` 來查看 Web-based console。

![](https://i.imgur.com/qgi39CC.png)

另外也可以進入 `:9090/metrics` 查看 Export metrics 資訊，並且可以在 console 來查詢指定 Metrics，並以圖表呈現。

![](https://i.imgur.com/Rv6XW6f.png)

Prometheus 提供了 [Functional Expression Language](https://prometheus.io/docs/prometheus/latest/querying/basics/) 進行查詢與聚合時間序列資料，比如用`sum(http_requests_total{method="GET"} offset 5m)`來查看指定時間的資訊總和。

Prometheus 提供拉取第三方或者自己開發的 Exporter metrics 作為監測資料，這邊可以透過簡單的 [Go Client](https://github.com/prometheus/client_golang.git) 範例來簡單部署 Exporter：
```sh
$ git clone https://github.com/prometheus/client_golang.git
$ cd client_golang/examples/random
$ go get -d
$ go build
```

完成後，開啟三個 Terminals 分別啟動以下 Exporter：
```sh
# terminal 1
$ ./random -listen-address=:8081

# terminal 2
$ ./random -listen-address=:8082

# terminal 3
$ ./random -listen-address=:8083
```
> 啟動後可以在`:8081`等 Ports 中查看 Metrics 資訊。

確定沒問題後，修改`prometheus.yml`來新增 target，並重新啟動 Prometheus Server：
```yaml
global:
  scrape_interval: 15s # 設定預設 scrape 的拉取間隔時間
  external_labels: # 外通溝通時標示在 time series 或 Alert 的 Labels。
    monitor: 'codelab-monitor'

scrape_configs: # 設定 scrape jobs
  - job_name: 'prometheus'
    scrape_interval: 5s # 若設定間隔時間，將會覆蓋 global 的預設時間。
    static_configs:
      - targets: ['localhost:9090']
  - job_name: 'example-random'
    scrape_interval: 5s
    static_configs:
      - targets: ['localhost:8080', 'localhost:8081']
        labels:
          group: 'production'
      - targets: ['localhost:8082']
        labels:
          group: 'canary'
```

啟動完成後，就可以 Web-console 的 Execute 執行以下來查詢：
```sh
avg(rate(rpc_durations_seconds_count[5m])) by (job, service)
```

![](https://i.imgur.com/Bo7YGo5.png)

另外 Prometheus 也提供自定義 Group rules 來將指定的 Expression query 當作一個 Metric，這邊建立一個檔案`prometheus.rules.yml`，並新增以下內容：
```yaml
groups:
- name: example
  rules:
  - record: job_service:rpc_durations_seconds_count:avg_rate5m
    expr: avg(rate(rpc_durations_seconds_count[5m])) by (job, service)
```

接著修改`prometheus.yml`加入以下內容，並重新啟動 Prometheus Server：
```yaml
global:
  ...
scrape_configs:
  ...
rule_files:
  - 'prometheus.rules.yml'
```
> `global` 與 `scrape_configs` 不做任何修改，只需加入`rule_files`即可，另外注意檔案路徑位置。

正常啟動後，就可以看到新的 Metric 被加入。
![](https://i.imgur.com/LhKcGVK.png)
