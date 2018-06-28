---
title: Kubernetes exec API 串接分析
date: 2018-6-25 17:08:54
layout: page
categories:
- Kubernetes
tags:
- Kubernetes
---
本篇將說明 Kubernetes exec API 的運作方式，並以簡單範例進行開發在前後端上。雖然 Kubernetes 提供了不同資源的 RESTful API 來進行 CRUD 操作，但是部分 API 並非單純的回傳一個資料，有些是需要透過 SPDY 或 WebSocket 建立長連線串流，這種 API 以 exec、attach 為主，目標是對一個 Pod 執行指定指令，或者進入該 Pod 進行互動等等。

<!---more-->

## Exec API Endpoint
首先了解一下 Kubernetes exec API endpoint，由於 Kubernetes 官方文件並未提供相關資訊，因此這邊透過 kubectl 指令來了解 API 的結構：
```shell=
$ cat <<EOF | kubectl create -f -
apiVersion: v1
kind: Pod
metadata:
  name: ubuntu
spec:
  containers:
  - name: ubuntu
    image: ubuntu:16.04
    command: ['/bin/bash', '-c', 'while :; do  echo Hello; sleep 1; done ']
EOF

$ kubectl -v=8 exec -ti ubuntu bash
...
I0625 10:39:33.716271   93099 round_trippers.go:383] POST https://xxx.xxx.xxx.xxx:8443/api/v1/namespaces/default/pods/ubuntu/exec?command=bash&container=ubuntu&container=ubuntu&stdin=true&stdout=true&tty=true
...
```

從上述得知 exec API 結構大致如下圖所示：

![](https://i.imgur.com/wMcqqMe.png)

其中 API 中的 Querys 又可細分以下資訊：
* **command**：將被執行的指令。若指令為`ping 8.8.8.8`，則 API 為`command=ping&command=8.8.8.8`。類型為`string`值。
* **container**：哪個容器將被執行指令。若 Pod 只有一個容器，一般會用 API 找出名稱塞到該參數中，若多個則選擇讓人輸入名稱。類型為`string`值。
* **stdin**：是否開啟標準輸入，通常由使用者決定是否開啟。類型為`bool`值。
* **stdout**：是否開啟標準輸出，通常是`預設開啟`。類型為`bool`值。
* **stderr**：是否開啟標準錯誤輸出，通常是`預設開啟`。類型為`bool`值。
* **tty**：是否分配一個偽終端設備(Pseudo TTY, PTY)。ㄒ為`bool`值。

## Protocol
Execute 是利用 SPDY 與 WebSocket 協定進行串流溝通的 API，其中 SPDY 在 Kubernetes 官方的 client-go 已經有實現(參考 [Remote command](https://github.com/kubernetes/client-go/blob/master/tools/remotecommand/remotecommand.go))，而 kubectl 正是使用 SPDY，但是 SPDY 目前已經規劃在未來將被[移棄](https://github.com/kubernetes/features/issues/384)，因此建議選擇使用 WebSocket 來作為串流溝通。但而無論是使用哪一個協定，都要注意請求的 Header 必須有`Connection: Upgrade`、`Upgrade: xxx`等，不然 API Server 會拒絕存取請求。

## HTTP Headers
除了 SPDY 與 WebSocket 所需要的 Headers(如 Upgrade 等)外，使用者與開發者還必須提供兩個 Headers 來確保能夠正確授權並溝通：

* **Authorization**：該 Header 是用來提供給 API Server 做認證請求的資訊，通常會是以`Authorization: Bearer <token>`的形式。
* **Accept**：指定客戶端能夠接收的內容類型，一般為`Accept: application/json`，若輸入不支援的類型將會被 API 以`406 Not Acceptable` 拒絕請求。

## 溝通協定
一旦符合上述所有資訊後，WebSocket(或 SPDY)就能夠建立連線，並且與 API Server 進行溝通。而當寫入 WebSocket 時，資料將被傳送到標準輸入(stdin)，而 WebSocket 的接收將會是標準輸出(stdout)與輸出錯誤(stderr)。Kubernetes API Server 簡單定義了一個協定來復用 stdout 與 stderr。因此可以理解當 WebSocket 建立連線後，傳送資料時需要再 Buffer 的第一個字元定義為 stdin(buf[0] = 0)，而接收資料時要判斷 stdout(buf[0] = 1) 與 stderr(buf[0] = 2)。其資訊如下：

| Code | 標準串流 |
|------|---------|
| 0    | stdin   |
| 1    | stdout  |
| 2    | stderr  |

下面簡單以發送`ls`指令為例：

```shell=
# 傳送`ls`指令，必須 buf[0] 自行塞入 0 字元來表示 stdin。
buf = [0 108 115 10]

# Receive
buf = [1 108 115 13 10 27 91 48 109 27 91 ...]
```
> 最後需要注意 Timeout 問題，由於可能對 WebSocket 設定 TCP Timeout，因此建議每一段時間發送一個 stdin 空訊息來保持連線。

實作參考一些專案自行練習寫了 Go 語言版本 [CLI](https://github.com/kairen/k8s-ws-exec)。
