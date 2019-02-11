---
title: 利用 Telepresence 提升本地 Kubernetes 開發效率
subtitle: ""
date: 2018-07-29 17:08:54
catalog: true
header-img: /images/kube/bg.png
categories:
- Kubernetes
tags:
- Kubernetes
- CNCF
- Telepresence
---
![](https://i.imgur.com/XDTlC4o.png)

Kubernetes 在經過這兩年快速發展，已漸漸成為容器編排系統的事實標準，這多虧了其易用性、擴展性與高可靠性等特性，再加上 Kubernetes 社區的各種 Toolchain 加持，讓 Kubernetes 更加完善，而這其中莫過於提供快速體驗 Kubernetes 的 Minikube 最受到關注，Minikube 幫助了許多剛踏入 Kubernetes 的使用者們得到快速體驗與開發，但是 Minikube 是透過虛擬機(Virtual Machine)來啟動一個單節點 Kubernetes 環境，這使得使用者需要提供更好規格的機器才能流暢的使用。而開源工具 [Telepresence](https://www.telepresence.io/) 提供了一個不同的方式來幫助開發者在本地端建構與測試服務，該工具透過雙向代理(Proxy)來遠端到一個叢集上，並使 Kubernetes 中的 Service、環境變數、Secrets 等在本地環境透明化，因此提升了開發的效率。Telepresence 目前是 CNCF Sandbox 的專案之一，其目的除了解決上述提到問題，也包含了以下幾點：

* 快速的開發單一服務，即使該服務依賴叢集中的其他服務，而對開發中的服務更改、保存等動作，都能讓你看到新服務的運行情況。
* 使用本地安裝的任何工具來 test、debug 與編輯服務，比如說透過 IDE 或 Debugger。
* 使你的本地開發機器看起來像是在 Kubernetes 叢集中運行一樣。

而 Telepresence 透過在 Kubernetes 叢集部署一個 two-way 網路代理的 Pod 來將遠端 Kubernetes 叢集環境(如 TCP 連線、環境變數與儲存等)的資料轉發到本地行程上，而本地行程會有它的覆蓋網路，以便透過代理路由 DNS 呼叫與 TCP 連接到遠端的 Kubernetes 叢集。而這具體的方法如下面所示：

* 本地服務可以完全存取遠端 Kubernetes 叢集的其他服務。
* 本地服務可以完全存取 Kubernetes 的還境變數、 Secrets 與 ConfigMap。
* 遠端服務可以完全存取本地服務。


- https://www.telepresence.io/discussion/overview
- https://www.ithome.com.tw/news/123529
