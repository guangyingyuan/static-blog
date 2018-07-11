---
title: 簡單部署 Docker Swarm 測試叢集
date: 2016-11-16 17:08:54
catalog: true
categories:
- Container
tags:
- Docker Swarm
- Docker
---
Docker Swarm 是 Docker 公司的 Docker 編配引擎，最早是在 2014 年 12 月發佈。Docker Swarm 目的即管理多台節點的 Docker 上應用程式與節點資源的排程等，並提供標準的 Docker API 介面當作前端存取入口，因此可以跟現有 Docker 工具與函式庫進行整合，本篇將介紹簡單的建立 Swarm cluster。

Docker Swarm 具備了以下幾個特性：
* Docker engine 原生支援。(Docker 1.12+)。
* 去中心化設計。
* 宣告式服務模型(Declarative Service Model)。
* 服務可擴展與容錯。
* 可協調預期狀態與實際狀態的一致性。
* 多種網路支援。
* 提供服務發現、負載平衡與安全策略。
* 支援滾動升級(Rolling Update)。

<!--more-->

## 基本架構
Docker Swarm 具備基本叢集功能，能讓多個 Docker 組合成一個群組，來提供容器服務。Docker 採用標準 Docker API 來管理容器的生命週期，而 Swarm 最主要核心是處理容器如何選擇一台主機來啟動容器這件事。以下為 Docker Swarm 架構：

![Docker](/images/docker/docker-swarm-architecture.png)

Docker Swarm 一般分為兩個角色`Manager`與`Worker`，兩者主要工作如下：
* **Manager**: 主要負責排程 Task，Task 可以表示為 Swarm 節點中的 Node 上啟動的容器。同時還負責編配容器與叢集管理功能，簡單說就是 Manager 具備管理 Node 的工作，除了以上外，Manager 還會維護叢集狀態。另外 Manager 也具備 Worker 的功能，當然也可以設定只做管理 Node 的職務。
* **Worker**: Worker 主要接收來自 Manager 的 Task 指派，並依據指派內容啟動 Docker 容器服務，並在完成後向 Manager 匯報 Task 執行狀態。

## 預先準備資訊
本教學將以下列節點數與規格來進行部署 Kubernetes 叢集，作業系統可採用`Ubuntu 16.x`與`CentOS 7.x`：

| IP Address  |   Role   |   CPU    |   Memory   |
|-------------|----------|----------|------------|
|172.16.35.12 |  manager |    1     |     2G     |
|172.16.35.10 |  node1   |    1     |     2G     |
|172.16.35.11 |  node2   |    1     |     2G     |

> 這邊 Manager 為主要控制節點，node 為應用程式工作節點。

首先安裝前要確認以下幾項都已將準備完成：
* 所有節點彼此網路互通，並且不需要 SSH 密碼即可登入。
* 所有防火牆與 SELinux 已關閉。如 CentOS：

```sh
$ systemctl stop firewalld && systemctl disable firewalld
$ setenforce 0
```

* 所有節點需要設定`/etc/host`解析到所有主機。
* 所有節點需要安裝`Docker`引擎，安裝方式如下：

```sh
$ curl -fsSL "https://get.docker.com/" | sh
```
> 不管是在 `Ubuntu` 或 `CentOS` 都只需要執行該指令就會自動安裝最新版 Docker。
> CentOS 安裝完成後，需要再執行以下指令：
```sh
$ systemctl enable docker && systemctl start docker
```

## Manager 節點建置
當我們完成安裝 Docker Engine 後，就可以透過 Docker 指令來初始化 Manager 節點：
```sh
$ docker swarm init --advertise-addr 172.16.35.12

Swarm initialized: current node (olluuvvz340ze64zhjpw03uke) is now a manager.

To add a worker to this swarm, run the following command:

    docker swarm join --token SWMTKN-1-0q0ohnexs40lb9z4kmvqb6zcrmp22hul9tmh6zpfztxzv5cv61-73yubitun1ufm0yhwx7h38p85 172.16.35.12:2377

To add a manager to this swarm, run 'docker swarm join-token manager' and follow the instructions.
```

當看到上述內容，表示 Manager 初始化完成，這時候可以透過以下指令檢查：
```sh
$ docker info
$ docker node ls
ID                            HOSTNAME            STATUS              AVAILABILITY        MANAGER STATUS
olluuvvz340ze64zhjpw03uke *   manager             Ready               Active              Leader
```

接著建立 Docker swarm network 來提供容器跨節點的溝通：
```sh
# Deploy network
$ docker network create --driver=overlay --attachable cnblogs

# Docker flow proxy network
$ docker network create --driver overlay proxy
```

檢查 Docker 網路狀態：
```sh
$ docker network ls | grep swarm
NETWORK ID          NAME                DRIVER              SCOPE
57nq0rux7akh        cnblogs             overlay             swarm
ihyg6uixeiov        ingress             overlay             swarm
b8vqturisod8        proxy               overlay             swarm
```

## Worker 節點建置
完成 Manager 初始化後，就可以透過以下指令來將節點加入叢集：
```sh
$ docker swarm join --token SWMTKN-1-0q0ohnexs40lb9z4kmvqb6zcrmp22hul9tmh6zpfztxzv5cv61-73yubitun1ufm0yhwx7h38p85 172.16.35.12:2377

This node joined a swarm as a worker.
```
> P.S. 其他節點一樣請用上述指令加入。

在`Manager`節點，查看節點狀態：
```sh
$ docker node ls
ID                            HOSTNAME            STATUS              AVAILABILITY        MANAGER STATUS
cwkta4o37daxed3otrqab9zdq     node2               Ready               Active
olluuvvz340ze64zhjpw03uke *   manager             Ready               Active              Leader
sfs49249kv8mad2qzr4ev4fy0     node1               Ready               Active
```

(option)將節點改為 Manager：
```sh
$ docker node promote <HOSTNAME>
```
> 另外降級為`docker node demote <HOSTNAME>`。

## 透過指令建立簡單服務
要建立 Docker 服務，可以使用`docker service`指令來達成，如下指令：
```sh
$ docker service create --replicas 1 --name ping alpine ping 8.8.8.8
$ docker service logs ping
ping.1.auqefe3iq9yk@node2    | PING 8.8.8.8 (8.8.8.8): 56 data bytes
ping.1.auqefe3iq9yk@node2    | 64 bytes from 8.8.8.8: seq=0 ttl=61 time=7.042 ms
ping.1.auqefe3iq9yk@node2    | 64 bytes from 8.8.8.8: seq=1 ttl=61 time=7.029 ms
ping.1.auqefe3iq9yk@node2    | 64 bytes from 8.8.8.8: seq=2 ttl=61 time=7.668 m
...
```

建立兩份副本數的應用，如以下指令：
```sh
$ docker service create --replicas 2 --name redis redis
$ docker service ps redis
ID                  NAME                IMAGE               NODE                DESIRED STATE       CURRENT STATE            ERROR               PORTS
ngtegx9vk4gu        redis.1             redis:latest        node1               Running             Running 43 seconds ago
n95vu3dzewu7        redis.2             redis:latest        manager             Running             Running 44 seconds ago
```

完成後，想要刪除可以使用以下指令：
```sh
$ docker service rm ping
$ docker service rm redis
```

## 部署簡單的 Stack
這邊利用簡單範例來部署應用程式於 Swarm 叢集中，首先新增`stack.yml`檔案，並加入以下內容：
```yaml
version: '3.2'
services:
  api:
    image: open-api:latest
    deploy:
      replicas: 2
      update_config:
        delay: 5s
      labels:
        - com.df.notify=true
        - com.df.distribute=true
        - com.df.serviceDomain=api.cnblogs.com
        - com.df.port=80
    networks:
      - cnblogs
      - proxy
networks:
  cnblogs:
    external: true
  proxy:
    external: true
```

完成後，透過以下指令來進行部署：
```sh
$ docker stack deploy -c stack.yml openapi
```
