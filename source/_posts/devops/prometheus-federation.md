---
title: 了解 Prometheus Federation 功能
catalog: true
comments: true
date: 2018-06-29 12:23:01
categories:
- DevOps
tags:
- DevOps
- Monitoring
- CNCF
- Prometheus
---
Prometheus 在效能上是能夠以單個 Server 支撐百萬個時間序列，當然根據不同規模的改變，Promethes 是能夠進行擴展的，這邊將介紹 Prometheus Federation 來達到此效果。

Prometheus Federation 允許一台 Prometheus Server 從另一台 Prometheus Server 刮取選定的時間序列資料。Federation 提供 Prometheus 擴展能力，這能夠讓 Prometheus 節點擴展至多個，並且能夠實現高可靠性(High Availability)與切片(Sharding)。對於 Prometheus 的 Federation 有不同的使用方式，一般分為`Cross-service federation`與`Hierarchical federation`。

<!--more-->

## Cross-service federation
這種方式的 Federation 會將一個 Prometheus Server 設定成從另一個 Prometheus Server 中獲取選中的時間序列資料，使得這個 Prometheus 能夠對兩個資料來源進行查詢(Query)與警告(Alert)，比如說有一個 Prometheus A 收集了多個服務叢集排程器曝露的資訊使用資訊(CPU、Memory 等)，而另一個在叢集上的 Promethues B 則只收集應用程式指定的服務 Metrics，這時想讓 Prometheus B 收集 Prometheus A 的資源使用量的話，就可以利用 Federation 來取得。

又或者假設想要監控 mysqld 與 node 的資訊，但是這兩個在不同叢集中，這時可以採用一個 Master Prometheus + 兩個 Sharding Prometheus，其中 Sharding Prometheus 一個收集 node_exporter 的 Metrics，另一個則收集 mysql_exporter，最後 Master Prometheus 透過 Federation 來匯總兩個 Sharding 的時間序列資料。

![](https://i.imgur.com/ism3t0M.png)

## Hierarchical federation
這種方式能夠讓 Prometheus 擴展到多個資料中心，或者多個節點數量，當建立一個 Federation 叢集時，其拓樸結構會類似一個樹狀結構，並且每一層級會有所對應的級別，比如說較高層級的 Prometheus Server 會從大量低層級的 Prometheus Server 中檢索或聚合時間序列資料。

![](https://i.imgur.com/dOinJCq.png)

這種方式適合當單一的 Prometheus 收集 Metrics 的任務(Job)量過大而無法負荷時，可將任務的實例(Instance)進行水平擴展，讓任務的目標實例拆分到不同 Prometheus 中，再由當前資料中心的主 Prometheus 來收集聚合。

## Federation 部署

### 節點資訊
測試環境將利用當一節點執行多個 Prometheus 來模擬，作業系統採用`Ubuntu 16.04 Server`，測試環境為實體機器：

| Name              | Role      | Port |
|-------------------|-----------|------|
| Prometheus-global | Master    | 9090 |
| Prometheus-node   | Collector | 9091 |
| Prometheus-docker | Collector | 9092 |

### 事前準備
開始安裝前需要確保以下條件已達成：

* 安裝與設定 Dockerd 提供 Metrics：

```sh
$ curl -fsSL "https://get.docker.com/" | sh

# 編輯 /etc/docker/daemon.json 加入下面內容
$ sudo vim /etc/docker/daemon.json
{
 "metrics-addr" : "127.0.0.1:9323",
 "experimental" : true
}

# 完成後重新啟動
$ sudo systemctl restart docker
$ curl 127.0.0.1:9323/metrics
```

* 透過 Docker 部署 Node Exporter：

```sh
$ docker run -d \
  --net="host" \
  --pid="host" \
  --name node-exporter \
  quay.io/prometheus/node-exporter

$ curl 127.0.0.1:9100/metrics
```

* 在模擬節點下載 Prometheus 伺服器執行檔：

```sh
$ wget https://github.com/prometheus/prometheus/releases/download/v2.3.0/prometheus-2.3.0.linux-amd64.tar.gz
$ tar xvfz prometheus-*.tar.gz
$ mv prometheus-2.3.0.linux-amd64 prometheus-2.3.0
$ cd prometheus-2.3.0
```

### 部署 Prometheus Federation
首先新增三個設定檔案，分別給 Global、Docker 與 Node 使用。

新增一個檔案`prometheus-docker.yml`，並加入以下內容:
```yaml=
global:
  scrape_interval:     15s
  evaluation_interval: 15s
  external_labels:
      server: 'docker-monitor'
scrape_configs:
  - job_name: 'docker'
    scrape_interval: 5s
    static_configs:
      - targets: ['localhost:9323']
```

新增一個檔案`prometheus-node.yml`，並加入以下內容:
```yaml=
global:
  scrape_interval:     15s
  evaluation_interval: 15s
  external_labels:
      server: 'node-monitor'
scrape_configs:
  - job_name: 'node'
    scrape_interval: 5s
    static_configs:
      - targets: ['localhost:9100']
```

新增一個檔案`prometheus-global.yml`，並加入以下內容:
```yaml=
global:
  scrape_interval:     15s
  evaluation_interval: 15s
  external_labels:
      server: 'global-monitor'
scrape_configs:
  - job_name: 'federate'
    scrape_interval: 15s
    honor_labels: true
    metrics_path: '/federate'
    params:
      'match[]':
        - '{job=~"prometheus.*"}'
        - '{job="docker"}'
        - '{job="node"}'
    static_configs:
      - targets:
        - 'localhost:9091'
        - 'localhost:9092'
```
> * 當設定 Federation 時，將透過 URL 中的 macth[] 參數指定需要獲取的時間序列資料，match[] 必須是一個向量選擇器資訊，如 up 或者 `{job="api-server"}` 等。
> * 設定`honor_labels`是避免資料衝突。

完成後，開啟三個 Terminal 來啟動 Prometheus Server：
```sh
# 啟動收集 Docker metrics 的 Prometheus server
$ ./prometheus --config.file=prometheus-docker.yml \
     --storage.tsdb.path=./data-docker \
	 --web.listen-address="0.0.0.0:9092"

# 啟動收集 Node metrics 的 Prometheus server
$ ./prometheus --config.file=prometheus-node.yml \
     --storage.tsdb.path=./data-node \
	 --web.listen-address="0.0.0.0:9091"

# 啟動收集 Global 的 Prometheus server
$ ./prometheus --config.file=prometheus-global.yml \
     --storage.tsdb.path=./data-global \
	 --web.listen-address="0.0.0.0:9090"
```

正常啟動後分別透過瀏覽器觀察`:9090`、`:9091`與`:9092`會發現 Master 會擁有 Node 與 Docker 的 Metrics，而其他兩者只會有自己所屬 Metrics。
> 注意，在 Alert 部分還是建議在各自 Sharding 的 Prometheus Server 處理，因為放到 Global 有可能會有接延遲。

### 部署 Grafana
在測試節點透過 Docker 部署 Grafana 來提供資料視覺化用：
```sh
$ docker run \
  -d \
  -p 3000:3000 \
  --name=grafana \
  -e "GF_SECURITY_ADMIN_PASSWORD=secret" \
  grafana/grafana
```

完成後透過瀏覽器查看`:3000`，並設定 Grafana 將 Prometheus Global 資料做呈現，請至`Configuration`的`Data Sources`進行設定。

![](https://i.imgur.com/vqGFTXA.png)


接著分別下載以下 Dashbaord JSON 檔案：

- [Node Exporter Server Metrics](https://grafana.com/api/dashboards/1860/revisions/12/download)
- [Docker Metrics](https://grafana.com/api/dashboards/1229/revisions/3/download)

並在 Grafana 點選 Import 選擇上面兩個下載的 JSON 檔案。

![](https://i.imgur.com/RdwP0vl.png)


Import 後選擇 Prometheus data source：

![](https://i.imgur.com/0NprMK4.png)

確認沒問題後點選`Import`，這時候就可以在 Dashboard 看到視覺化的 Metrics 了。

![](https://i.imgur.com/AgSahRP.png)

Docker Metrics 資訊：

![](https://i.imgur.com/Tjpc4Fs.png)

更多的 Dashboard 可以至官方 [Dashboards](https://grafana.com/dashboards) 尋找。

## Prometheus Federation 不適用地方
經上述兩者說明，可以知道 Prometheus Federation 大多被用來從另一個 Prometheus 拉取受限或聚合的時間序列資料集，但是不只上述功能，該 Prometheus 本身還是要肩負警報(Alert)與圖形(Graph)資料查詢工作。而什麼狀況是 Prometheus Federation 不適用的？那就是使用在從另一個 Prometheus 拉取大量時間序列(甚至所有時間序列資料)，並且只從該 Prometheus 做警報(Alert)與圖形(Graph)處理。

這邊列出三個原因：

* **效能(Performance)與縮放(Scaling)問題**：Prometheus 的限制因素主要是一台機器所能處理的時間序列資料量，然而讓所有資料路由到一個 Global 的 Prometheus Server 將限制這台 Server 所能處理的監控。取而代之，若只拉取聚合的時間序列資料，只限於一個資料中心的 Prometheus 能夠處理，因此請允許新增資料中心來避免擴大 Global Prometheus。而 Federation 請求本身也能夠大量地服務於接收 Prometheus。

* **可靠性(Reliability)**：如果需要進行警報(Alert)的資料從一個 Prometheus 移動到另一個時，那麼這樣就會多出一個額外的故障點。當牽扯到諸如互聯網之類的廣域網路連接時，是特別危險的。在可能的情況下，應該盡量將警報(Alert)推送到 Federation 層級較深的 Prometheus上。

* **正確性(Correctness)**：由於工作原理關析，Federation 會在被刮取(scraped)後的某一段時間拉取資料，並且可能因 Race 問題而遺失一些資料。雖然這問題在 Global Promethesu 能夠被容忍，但是用於處理警報(Alert)與圖表查詢的資料中心 Prometheus 就可能造成問題。
