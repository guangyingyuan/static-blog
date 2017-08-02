---
title: 自己建立 Docker Registry
date: 2016-1-02 17:08:54
layout: page
categories:
- Container
tags:
- Linux Container
- Docker
- Docker registry
---
Docker Registry 是被用來儲存 Docker 所建立的映像檔的地方，我們可以把自己建立的映像檔透過上傳到 Registries 來分享給其他人。Registries 也被分為了公有與私有，一般公有的 Registries 是 [Docker Hub](https://hub.docker.com/)、[QUAY](https://quay.io/) 與 [GCP registry](https://console.cloud.google.com/gcr/images/google-containers/GLOBAL)，提供了所有基礎的映像檔與全球使用者上傳的映像檔。私人的則是企業或者個人環境建置的，可參考 [Deploying a registry server](https://docs.docker.com/registry/deploying/)。

<!--more-->

## 預先準備資訊
本教學將以下列節點數與規格來進行部署 Kubernetes 叢集，作業系統可採用`Ubuntu 16.x`與`CentOS 7.x`：

| IP Address  |   Role          |   CPU    |   Memory   |
|-------------|-----------------|----------|------------|
|172.16.35.13 | docker-registry |    1     |     2G     |

### 安裝
首先進入到`docker-registry`節點，安裝 Docker engine：
```sh
$ curl -fsSL "https://get.docker.com/" | sh
```

完成安裝後，接著透過以下指令建立一個 Docker registry 容器：
```sh
$ docker run -d -p 5000:5000 --restart=always --name registry \
-v $(pwd)/data:/var/lib/registry \
registry:2
```
> -v 為 host 與 container 要進行同步的目錄，主要存放 docker images 資料

接著為了方便檢視 Docker image，這邊另外部署 Docker registry UI：
```sh
$ docker run -d -p 5001:80 \
-e ENV_DOCKER_REGISTRY_HOST=172.16.35.13 \
-e ENV_DOCKER_REGISTRY_PORT=5000 \
konradkleine/docker-registry-frontend:v2
```

完成後就可以透過瀏覽器進入 [Docker registry UI](172.16.35.13:5001) 查看資訊。也可以透過以下指令檢查是否部署成功：
```sh
$ docker pull ubuntu:14.04
$ docker tag ubuntu:14.04 localhost:5000/ubuntu:14.04
$ docker push localhost:5000/ubuntu:14.04

The push refers to a repository [localhost:5000/ubuntu]
447f88c8358f: Pushed
df9a135a6949: Pushed
...
```
> 其他 Docker registry 列表：
> * [Portus](https://github.com/SUSE/Portus)
> * [Atomic Registry](http://www.projectatomic.io/registry/)
> * [Private Registries in RancherOS](https://docs.rancher.com/os/configuration/private-registries/)
> * [VMware Harbor](https://github.com/vmware/harbor)
