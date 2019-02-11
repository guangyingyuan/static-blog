---
title: Prometheus 高可靠實現方式
catalog: true
comments: true
date: 2018-07-01 12:23:01
categories:
- DevOps
tags:
- DevOps
- Monitoring
- CNCF
- Prometheus
---
前面幾篇提到了 Prometheus 儲存系統與 Federation 功能，其中在儲存系統可以得知 Local on-disk 方式雖然能夠帶來很好的效能，但是卻也存在著單點故障的問題，並且限制了 Prometehsu 的可擴展性，引發資料的持久等問題，也因此 Prometheus 提供了遠端儲存(Remote storage)的特性來解決擴展性問題。

而除了儲存問題外，另一方面就是要考量單一 Prometheus 在大規模環境下的採集樣本效能與乘載量(所能夠處理的時間序列資料)，因此這時候可以利用 Federation 來將不同監測任務劃分到不同實例當中，以解決單台 Prometheus 無法有效處理的狀況。

而本節主要探討各種 Prometheus 的高可靠(High Availability)架構。

{% colorquote info %}
這邊不探討 Alert Manager 如何實現高可靠性架構。
{% endcolorquote %}

## 服務的高可靠性架構(最基本的 HA)
從前面介紹可以得知 Promehteus 是以 Pull-based 進行設計，因此收集時間序列資料(Mtertics)都是透過 Prometheus 本身主動發起，而為了保證 Prometheus 服務能夠正常運作，這邊只需要建立多台 Prometheus 節點來收集同樣的 Metrics(同樣的 Exporter target)即可。

![](https://i.imgur.com/ryuQexH.png)

這種做法雖然能夠保證服務的高可靠，但是並無法解決不同 Prometheus Server 之間的資料`一致性`問題，也無法讓取得的資料進行`長時間儲存`，且當規模大到單一 Prometheus 無法負荷時，將延伸出效能瓶頸問題，因此這種架構只適合在小規模叢集進行監測，且 Prometheus Server 處於的環境比較不嚴苛，也不會頻繁發生遷移狀況與儲存長週期的資料(Long-term store)。

上述總結：

* **Pros**:
	* 服務能夠提供可靠性
	* 適合小規模監測、只需要短期資料儲存(5ms)、不用經常遷移節點
* **Cons**:
	* 無法動態擴展
	* 資料會有不一致問題
	* 資料無法長時間儲存
	* 不適合在頻繁遷移的狀況
	* 當乘載量過大時，單一 Prometheus Server 會無法負荷

## 服務高可靠性結合遠端儲存(基本 HA + Remote Storage)
這種架構即在基本 HA 上加入遠端儲存功能，讓 Prometheus Server 的讀寫來至第三方儲存系統。

![](https://image.ibb.co/iNkteo/prometheus_remote_ha_storage.png)

該架構解決了資料持久性儲存問題，且當 Prometheus Server 發生故障或者當機時，重新啟動能夠快速的恢復資料，同時 Prometheus Server 能夠更好睇進行遷移，但是這只適合在較小規模的監測使用。

上述總結：

* **Pros**:
	* 服務能夠提供可靠性
	* 適合小規模監測
	* 資料能夠被持久性保存在第三方儲存系統
	* Prometheus Server 能夠遷移
	* 能夠達到資料復原
* **Cons**:
	* 不適合大規模監測
	* 當乘載量過大時，單一 Prometheus Server 會無法負荷

## 服務高可靠性結合遠端儲存與聯邦(基本 HA + Remote Storage + Federation)
這種架構主要是解決單一 Promethes Server 無法處理大量資料收集任務問題，並且加強 Prometheus 的擴展性，透過將不同收集任務劃分到不同 Prometheus 實例上。

![](https://i.imgur.com/JAwV0cH.png)

該架構通常有兩種使用場景：

* **單一資料中心，但是有大量的收集任務**：這種場景下 Prometheus Server 可能會發生效能上瓶頸，主要是單一 Prometheus Server 要乘載大量的資料收集任務，這時候就能夠透過 Federation 來將不同類型的任務分到不同的子 Prometheus Server 上，再由最上層進行聚合資料。

* **多資料中心**：在多資料中心下，這種架構也能夠適用，當不同資料中心的 Exporter 無法讓最上層的 Prometheus 去拉取資料時，就能透過 Federation 來進行分層處理，在每個資料中心建置一組收集該資料中心的子 Prometheus Server，再由最上層的 Prometheus 來進行抓取，並且也能夠依據每個收集任務的乘載量來部署與劃分層級，但是這需要確保上下層的 Prometheus Server 彼此能夠互相溝通。

上述總結：

* **Pros**:
	* 服務能夠提供可靠性
	* 資料能夠被持久性保存在第三方儲存系統
	* Prometheus Server 能夠遷移
	* 能夠達到資料復原
	* 能夠依據不同任務進行層級劃分
	* 適合不同規模監測
	* 能夠很好的擴展 Prometheus Server
* **Cons**:
	* 部署架構複雜
	* 維護困難性增加
	* 在 Kubernetes 上部署不易

## 單一收集任務的實例(Scrape Target)過多問題
這問題可能發生在單個 Job 設定太多 Target 數，這時候透過 Federation 來區分可能也無法解決問題，這種情況下只能透過在實例(Instance)級別進行功能劃分。這種做法是將不同實例的資料收集劃分到不同 Prometheus Server 實例，再透過 `Relabel` 設定來確保當前的 Prometheus Server 只收集當前收集任務的一部分實例監測資料。

一個簡單範例組態檔：
```yaml=
global:
  external_labels:
    slave: 1  # This is the 2nd slave. This prevents clashes between slaves.
scrape_configs:
  - job_name: some_job
    # Add usual service discovery here, such as static_configs
    relabel_configs:
    - source_labels: [__address__]
      modulus:       4    # 4 slaves
      target_label:  __tmp_hash
      action:        hashmod
    - source_labels: [__tmp_hash]
      regex:         ^1$  # This is the 2nd slave
      action:        keep
```

## Refers
- https://prometheus.io/docs/introduction/faq/#can-prometheus-be-made-highly-available
- https://github.com/coreos/prometheus-operator/blob/master/Documentation/high-availability.md
- https://github.com/coreos/prometheus-operator
- https://coreos.com/operators/prometheus/docs/latest/high-availability.html
