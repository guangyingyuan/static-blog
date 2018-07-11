---
title: Enterprise 的 Docker registry 平台 Harbor
date: 2017-5-10 17:08:54
catalog: true
categories:
- Container
tags:
- Linux Container
- Docker
- Docker registry
---
Harbor 是一個企業級 Registry 伺服器用於儲存和分散 Docker Image 的，透過新增一些企業常用的功能，例如：安全性、身分驗證和管理等功能擴展了開源的 [Docker Distribution](https://github.com/docker/distribution)。作為一個企業級的私有 Registry 伺服器，Harbor 提供了更好的效能與安全性。Harbor 支援安裝多個 Registry 並將 Image 在多個 Registry 做 replicated。除此之外，Harbor 亦提供了高級的安全性功能，像是用戶管理(user managment)，存取控制(access control)和活動審核(activity auditing)。

![](/images/docker/harbor_logo.png)
<!--more-->

## 功能特色
- **基於角色為基礎的存取控制(Role based access control)**：使用者和 Repository 透過 Project 進行組織管理，一個使用者在同一個 Project 下，對於每個 Image 可以有不同權限。
- **基於 Policy 的 Image 複製**：Image 可以在多得 Registry instance 中同步複製。適合於附載平衡、高可用性、混合雲與多雲的情境。
- **支援 LDAP/AD**：Harbor 可以整合企業已有的 LDAP/AD，來管理使用者的認證與授權。
- **使用者的圖形化介面**：使用者可以透過瀏覽器，查詢 Image 和管理 Project
- **審核管理**：所有對 Repositroy 的操作都被記錄。
- **RESTful API**：RESTful APIs 提供給管理的操作，可以輕易的整合額外的系統。
- **快速部署**：提供 Online installer 與 Offline installer。

## 安裝指南
Harbor 提供兩種方法進行安裝：
1. Online installer
    這種安裝方式會從 Docker hub 下載 Harbor 所需的映像檔，因此 installer 檔案較輕量。
2. Offline installer
    當無任何網際網路連接的情況下使用此種安裝方式，預先將所需的映像檔打包，因此 installer 檔案較大。

### 事前準備
Harbor 會部署數個 Docker container，所以部署的主機需要能支援 Docker 的 Linux distribution。而部署主機需要安裝以下套件：
* Python 版本`2.7+`。
* Docker Engine 版本 `1.10+`。Docker 安裝方式，請參考：[Install Docker](https://docs.docker.com/engine/installation/)
* Docker Compose 版本 `1.6.0+`。Docker Compose 安裝方式，請參考：[Install Docker Compose](https://docs.docker.com/compose/install/)

> 官方安裝指南說明是 Linux 且要支援 Docker，但 Windows 支援 Docker 部署 Harbor 還需要驗證是否可行。

安裝步驟大致可分為以下階段：
1. 下載 installer
2. 設定 Harbor
3. 執行安裝腳本

#### 下載 installer
installer 的二進制檔案可以從 [release page](https://github.com/vmware/harbor/releases) 下載，選擇您需要 Online installer 或者 Offline installer，下載完成後，使用`tar`將 package 解壓縮：

Online installer：
```sh
$ tar xvf harbor-online-installer-<version>.tgz
```

Offline installer：
```sh
$ tar xvf harbor-offline-installer-<version>.tgz
```

#### 設定 Harbor
Harbor 的設定與參數都在`harbor.cfg`中。

`harbor.cfg`中的參數分為**required parameters**與**optional parameters**
* **required parameters**
    這類的參數是必須設定的，且會影響使用者更新`harbor.cfg`後，重新執行安裝腳本來重新安裝 Harbor。
* **optional parameters**
    這類的參數為使用者自行決定是否設定，且只會在第一次安裝時，這些參數的配置才會生效。而 Harbor 啟動後，可以透過 Web UI 進行修改。

##### Configuring storage backend (optional)
預設的情況下，Harbor 會將 Docker image 儲存在本機的檔案系統上，在生產環境中，您可以考慮使用其他 storage backend 而不是本機的檔案系統，像是 S3, OpenStack Swift, Ceph 等。而僅需更改 `common/templates/registry/config.yml`。以下為一個接 OpenStack Swift 的範例：
```sh
storage:
  swift:
    username: admin
    password: ADMIN_PASS
    authurl: http://keystone_addr:35357/v3/auth
    tenant: admin
    domain: default
    region: regionOne
    container: docker_images
```
> 更多 storage backend 的資訊，請參考：[Registry Configuration Reference](https://docs.docker.com/registry/configuration/)。
> 另外官方提供的是改 `common/templates/registry/config.yml`，感覺寫錯，需再測試其正確性。

#### 執行安裝腳本
一旦`harbor.cfg`與 storage backend (optional) 設定完成後，可以透過`install.sh`腳本開始安裝 Harbor。從 Harbor 1.1.0 版本之後，已經整合`Notary`，但是預設的情況下安裝是不包含`Notary`支援：
```sh
$ sudo ./install.sh
```
> Online installer 會從 Docker hub 下載 Harbor 所需的映像檔，因此會花較久的時間。

如果安裝過程正常，您可以打開瀏覽器並輸入在`harbor.cfg`中設定的`hostname`，來存取 Harbor 的 Web UI。
![Harbor Web UI](https://i.imgur.com/jBVsr49.png)
> 預設的管理者帳號密碼為 `admin`/`Harbor12345`。

#### 開始使用 Harbor
登入成功後，可以創建一個新的 Project，並使用 Docker command 進行登入，但在登入之前，需要對 Docker daemon 新增`--insecure-registry`參數。新增`--insecure-registry`參數至`/etc/default/docker`中：
```sh
DOCKER_OPTS="--insecure-registry <your harbor.cfg hostname>"
```
> 其他細節，請參考：[Test an insecure registry](https://docs.docker.com/registry/insecure/#deploying-a-plain-http-registry)。

> 若在`Ubuntu 16.04`的作業系統版本，需要修改`/lib/systemd/system/docker.service`檔案，並加入一下內容。另外在 CentOS 7.x 版本則不需要加入`-H fd://`資訊：
```sh
EnvironmentFile=/etc/default/docker
ExecStart=/usr/bin/dockerd -H fd:// $DOCKER_OPTS
```

修改完成後，重新啟動服務：
```sh
$ sudo systemctl daemon-reload
```

服務重啟成功後，透過 Docker command 進行 login：
```sh
$ docker login <your harbor.cfg hostname>
```

將映像檔上 tag 之後，上傳至 Harbor：
```sh
$ docker tag ubuntu:<your harbor.cfg hostname>/<your project>/ubuntu:16.04
$ docker push <your harbor.cfg hostname>/<your project>/ubunut:16.04
```

從 Harbor 抓取上傳的映像檔：
```sh
$ docker pull <your harbor.cfg hostname>/<your project>/ubunut:16.04
```
> 更多使用者操作，請參考：[Harbor User Guide](https://github.com/vmware/harbor/blob/master/docs/user_guide.md)。
