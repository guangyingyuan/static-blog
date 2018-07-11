---
title: Apache Flume 快速上手
date: 2016-4-04 17:08:54
catalog: true
categories:
- Spark
tags:
- Spark
- Logging
---
Apache Flume 是一個分散式日誌收集系統，是由 Cloudera 公司開發的一款高效能、高可靠性和高恢復性的系統。它能從不同來源的大量日誌資料進行高效收集、聚合、移動，最後儲存到一個資料中心儲存系統當中。架構經過重構後，從原來的 Flume OG 到現在的 Flume NG。Flume NG 更像一個輕量化的小套件，簡單使用且容易適應不同方式收集日誌，且支援 Failover 和 Load Balancing

<!--more-->

## 架構角色說明
Flume 架構中主要有以下幾個核心:
* **Event**：一個資料單元，會附帶一個可選的訊息來源。ex:日誌紀錄、avro。
* **Client**：操作位在原點的 Event 且將它傳送到 Flume Agent，主要是產生資料，運行在一個獨立程式。
* **Agent**：一個獨立的 Flume 程式，包含 Source、Channel、Sink。
* **Source**：用來消費從 Client 端收集資料到此的 Event，然後傳送到 Channel。
* **Channel**：轉換 Event 的一個臨時儲存空間，保有從 Source 傳送過來的 Event。
* **Sink**:從 Channel 中讀取並且移除 Event，將 Event 傳遞到 Flow Pipeline 的下一個 Agent（如果存在的話）。

<center>![](/images/spark/flume_architecture.png)</center>

## 安裝 Apache Flume
本節將說明如何部署 Apache Flume，其中包含單機與多機部署方式。

### 單機
首先節點需先安裝 Java，這邊採用 Oracle 的 Java8 來進行安裝：
```sh
$ sudo add-apt-repository -y ppa:webupd8team/java
$ sudo apt-get update
$ sudo apt-get install -y oracle-java8-installer
```

完成後，在主機上安裝下載 Flume 套件，使用`wget`下載：
```sh
$ wget "ftp://ftp.twaren.net/Unix/Web/apache/flume/1.6.0/apache-flume-1.6.0-src.tar.gz"
$ wget "ftp://ftp.twaren.net/Unix/Web/apache/flume/1.6.0/apache-flume-1.6.0-bin.tar.gz"
$ tar zxvf apache-flume-1.6.0-src.tar.gz
$ tar zxvf apache-flume-1.6.0-bin.tar.gz
```

下載完後，將 src 覆蓋到 bin 底下，並解壓縮到`/opt`底下:
```sh
$ sudo cp -ri apache-flume-1.6.0-src/* apache-flume-1.6.0-bin
$ sudo mv /opt/apache-flume-1.5.0-bin /opt/flume
```

之後到`/opt/flume/conf`底下建立 example 配置檔:
```sh
$ sudo vim example.conf
```

設定以下內容:
```
# example.conf: A single-node Flume configuration

# Name the components on this agent
a1.sources = r1
a1.sinks = k1
a1.channels = c1

# Describe/configure the source
a1.sources.r1.type = netcat
a1.sources.r1.bind = localhost
a1.sources.r1.port = 44444

# Describe the sink
a1.sinks.k1.type = logger

# Use a channel which buffers events in memory
a1.channels.c1.type = memory
a1.channels.c1.capacity = 1000
a1.channels.c1.transactionCapacity = 100

# Bind the source and sink to the channel
a1.sources.r1.channels = c1
a1.sinks.k1.channel = c1
```

之後啟動 Flume:
```sh
$ bin/flume-ng agent -c conf -f example.conf -n a1 -Dflume.root.logger=INFO,console
```
>`-c/--conf`設定檔目錄，`-f/--conf-file`設定檔案路徑，`-n/--name`指定 agent 的名稱

驗證 Flume 開啟是否已開啟
```sh
$ jps
6760 Jps
6623 Application
```

最後開 shell 終端窗口，telnet 到配置監聽 port:
```
$ telnet localhost 44444
# 輸入
HI!
OK

# 輸出
2016-02-24 11:40:30,389 INFO sink.LoggerSink: Event: { headers:{} body: 48 65 6C 6C 6F 20 77 6F 72 6C 64 21 0D          HI!. }
```

### 多節點部署
本節說明多機部署方式，流程為 Agent1 和 Agent2 主要是兩個來源蒐集端，本身會監聽且接收 Flume 本地端的訊息，然後將資料整合到 Collector 做資料日誌整理

<center>![](/images/spark/flume_cluster.png)</center>

部署節點角色規則如下:

|  IP Address  |	Role   	|
|--------------|------------|
|192.168.100.94|  Agent1 	|
|192.168.100.96|  Agent2 	|
|192.168.100.97|  Collector |

一開始安裝配置與單機相同，從第一步驟到下載完後，將 src 覆蓋到 bin 底下，並解壓縮到`/opt`底下

然後到各自的`/opt/flume/conf`底下建立配置檔

`Agent1`和`Agent2`配置內容如下:
```
# flume-client.properties: Agent1 Flume configuration

#agent1 name
agent1.sources = r1
agent1.sinks = k1
agent1.channels = c1

#set gruop
agent1.sinkgroups = g1

#set channel
agent1.channels.c1.type = memory
agent1.channels.c1.capacity = 1000
agent1.channels.c1.transactionCapacity = 100

#set source
agent1.sources.r1.channels = c1
agent1.sources.r1.type = netcat
agent1.sources.r1.bind = localhost
agent1.sources.r1.port = 52020

agent1.sources.r1.interceptors = i1
agent1.sources.r1.interceptors.i1.type = static
agent1.sources.r1.interceptors.i1.key = Type
agent1.sources.r1.interceptors.i1.value = LOGIN

# set sink
agent1.sinks.k1.channel = c1
agent1.sinks.k1.type = avro
agent1.sinks.k1.hostname = 192.168.100.97
agent1.sinks.k1.port = 44444

#set sink group
agent1.sinkgroups.g1.sinks = k1

#set failover
agent1.sinkgroups.g1.processor.type = failover
agent1.sinkgroups.g1.processor.priority.k1 = 10
agent1.sinkgroups.g1.processor.maxpenalty = 10000
```

`Collector` 配置內容如下:
```sh
# flume-server.properties: Agent1 Flume configuration

#set Agent name
a1.sources = r1
a1.sinks = k1
a1.channels = c1

#set channel
a1.channels.c1.type = memory
a1.channels.c1.capacity = 1000
a1.channels.c1.transactionCapacity = 100

#set source
a1.sources.r1.type = avro
a1.sources.r1.bind = 192.168.100.97
a1.sources.r1.port = 44444
a1.sources.r1.interceptors = i1
a1.sources.r1.interceptors.i1.type = static
a1.sources.r1.interceptors.i1.key = Collector
a1.sources.r1.interceptors.i1.value = NNA
a1.sources.r1.channels = c1

# set sink
a1.sinks.k1.type=logger
a1.sinks.k1.channel=c1
```

最後分別啓動`Agent`和`Collector`的 Flume
>Agent:
```sh
$ bin/flume-ng agent -n agent1 -c conf -f flume-client.properties -Dflume.root.logger=DEBUG,console
```


>Collector:
```sh
$ bin/flume-ng agent -n a1 -c conf -f flume-server.properties -Dflume.root.logger=DEBUG,console
```
