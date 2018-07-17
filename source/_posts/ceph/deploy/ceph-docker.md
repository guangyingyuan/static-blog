---
catalog: true
title: Docker 快速部署 Ceph 測試叢集
date: 2016-2-11 17:08:54
categories:
- Ceph
tags:
- Ceph
- Storage
- Docker
---
本節將介紹如何透過 [ceph-docker](https://github.com/ceph/ceph-docker) 工具安裝一個測試的 Ceph 環境，一個最簡單的 Ceph 儲存叢集至少要`1 Monitor`與`3 OSD`。另外部署 MDS 與 RGW 來進行簡單測試。

![](/images/ceph/docker-ceph.jpg)

<!--more-->

## 節點配置
本安裝採用一台虛擬機器來提供部署，可使用 VBox 或 OpenStack 等建立，其環境資源大小如下：

| hostname  | CPUs  |  RAM  |
|-----------|-------|-------|
| ceph-aio  | 2vCPU |  4GB  |

> 若使用 Vagrant + VBox 的話，可以使用 [Vagrantfile 腳本](https://gist.githubusercontent.com/kairen/c55a436718ddc22817ef820001aecb0f/raw/4be0a6cfa5087a4834494779b0809d76d701f67b/Vagrantfile)。

而該虛擬機要額外建立三顆虛擬區塊裝置，如下所示：

| Dev path  | Disk  | Description|
|-----------|-------|------------|
| /dev/sdb  | 20 GB | osd-1 使用  |
| /dev/sdc  | 20 GB | osd-2 使用  |
| /dev/sdd  | 20 GB | osd-3 使用  |

## 事前準備
首先在主機安裝 Docker Engine，可以透過以下指令進行安裝：
```sh
$ curl -fsSL https://get.docker.com/ | sh
```

## 部署 Ceph 測試叢集
首先為了不與預設 Docker 網路共用，這邊額外建立一網路來提供給 Ceph 使用：
```sh
$ docker network create --driver bridge ceph-net
$ docker network inspect ceph-net
{
    "Subnet": "172.18.0.0/16",
    "Gateway": "172.18.0.1/16"
}
```

### 建立 Monitor
完成網路建立後，就可以開始部署 Ceph 叢集了。一開始我們必須先建立 Monitor Container：
```sh
$ cd ~ && DIR=$(pwd)
$ sudo docker run -d --net=ceph-net \
-v ${DIR}/ceph:/etc/ceph \
-v ${DIR}/lib/ceph/:/var/lib/ceph/ \
-e MON_IP=172.18.0.2 \
-e CEPH_PUBLIC_NETWORK=172.18.0.0/16 \
--name mon1 \
ceph/daemon mon
```
> 若發生錯誤請刪除以下目錄。如以下指令：
```sh
$ sudo rm -rf ${DIR}/etc/ceph/
$ sudo rm -rf ${DIR}/var/lib/ceph/
```

檢查是否正確部署：
```sh
$ docker exec -ti mon1 ceph -v
ceph version 10.2.2 (45107e21c568dd033c2f0a3107dec8f0b0e58374)

$ docker exec -ti mon1 ceph -s
cluster 2c254496-e948-4abb-a6dc-9aea41bbb56a
 health HEALTH_ERR
        no osds
 monmap e1: 1 mons at {1068f41de69a=172.18.0.2:6789/0}
        election epoch 3, quorum 0 1068f41de69a
 osdmap e1: 0 osds: 0 up, 0 in
        flags sortbitwise
  pgmap v2: 64 pgs, 1 pools, 0 bytes data, 0 objects
        0 kB used, 0 kB / 0 kB avail
              64 creating
```

### 建立 OSD
上面可以看到 Monitor 建立完成，但是會有錯誤，因為目前沒有 OSD。因此這邊將建立三個 OSD Container 來模擬叢集做實際儲存的功能，透過以下方式部署：
```sh
$ cd ~ && DIR=$(pwd)
$ sudo docker run -d --net=ceph-net \
--privileged=true --pid=host \
-v ${DIR}/ceph:/etc/ceph \
-v ${DIR}/lib/ceph/:/var/lib/ceph/ \
-v /dev/:/dev/ \
-e OSD_DEVICE=/dev/sdb \
-e OSD_TYPE=disk \
-e OSD_FORCE_ZAP=1 \
--name osd1 \
ceph/daemon osd
```
> 若要建立多個 OSD，只需要修改`OSD_DEVICE`與`name`即可，這邊建議建立三個 OSD。因為預設 pool 採用三份副本，若節點數過少需要自行修改副本數或 CRUSH Map。

完成後，可以透過以下指令檢查 Device 被使用：
```sh
$ docker exec -ti osd1 df | grep "osd"
/dev/sdb1                     20857836   34924  20822912   1% /var/lib/ceph/osd/ceph-0
```

也可以直接透過 Monitor 來查看叢集安全狀態，如 PG 是否有誤等：
```sh
$ docker exec -ti mon1 ceph -s
cluster 23fa3f2c-a401-46e0-abc1-d71b4625b348
 health HEALTH_OK
 monmap e2: 1 mons at {0b7ff674673f=172.18.0.2:6789/0}
        election epoch 4, quorum 0 0b7ff674673f
    mgr no daemons active
 osdmap e15: 3 osds: 3 up, 3 in
        flags sortbitwise,require_jewel_osds,require_kraken_osds
  pgmap v29: 64 pgs, 1 pools, 0 bytes data, 0 objects
        101 MB used, 61005 MB / 61106 MB avail
              64 active+clean
```

### 建立 RGW
當完成一個 RAODS(MON+OSD)叢集後，即可建立物件儲存閘道(RAODS Gateway)提供 S3 與 Swift 相容的 API，來儲存檔案到叢集中，一個 RGW Container 建立如下所示：
```sh
$ cd ~ && DIR=$(pwd)
$ sudo docker run -d --net=ceph-net \
-v ${DIR}/lib/ceph/:/var/lib/ceph/ \
-v ${DIR}/ceph:/etc/ceph \
-p 8080:8080 \
--name rgw1 \
ceph/daemon rgw
```

完成後，透過 curl 工具來測試是否正確部署：
```sh
$ curl -H "Content-Type: application/json" "http://127.0.0.1:8080"
<?xml version="1.0" encoding="UTF-8"?><ListAllMyBucketsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Owner><ID>anonymous</ID><DisplayName></DisplayName></Owner><Buckets></Buckets></ListAllMyBucketsResult>
```

透過 Python Client 進行檔案儲存，首先下載程式：
```sh
$ wget "https://gist.githubusercontent.com/kairen/e0dec164fa6664f40784f303076233a5/raw/33add5a18cb7d6f18531d8d481562d017557747c/s3client"
$ chmod u+x s3client
$ sudo pip install boto
```

接著透過以下指令建立一個使用者：
```sh
$ docker exec -ti rgw1 radosgw-admin user create --uid="test" --display-name="I'm Test account" --email="test@example.com"

"keys": [
        {
            "user": "test",
            "access_key": "PFMKGXCFD77L8X4CF0T4",
            "secret_key": "SA8RpGO7SoN4TIdRxYtxloc5kRSLQvhOihJdDGG3"
        }
    ],
```

建立一個放置環境參數的檔案`s3key.sh`：
```sh
export S3_ACCESS_KEY="PFMKGXCFD77L8X4CF0T4"
export S3_SECRET_KEY="SA8RpGO7SoN4TIdRxYtxloc5kRSLQvhOihJdDGG3"
export S3_HOST="127.0.0.1"
export S3_PORT="8080"
```

然後 source 檔案，並嘗試執行列出 bucket 指令：
```sh
$ . s3key.sh
$ ./s3client list
---------- Bucket List ----------
```

建立一個 Bucket，並上傳檔案：
```sh
$ ./s3client create files
Create [files] success ...

$ ./s3client upload files s3key.sh /
Upload [s3key.sh] success ...
```

完成後，即可透過 list 與 download 來查看與下載：
```sh
$ ./s3client list files
---------- [files] ----------
s3key.sh            	157                 	2016-07-26T06:48:14.327Z

$ ./s3client download files s3key.sh
Download [s3key.sh] success ...
```

### 建立 MDS
當系統需要使用到 CephFS 時，我們將必須建立 MDS(Metadata Server) 來提供詮釋資料的儲存，一個 MDS 容器部署如下：
```sh
$ cd ~ && DIR=$(pwd)
$ sudo docker run -d --net=ceph-net \
-v ${DIR}/lib/ceph/:/var/lib/ceph/ \
-v ${DIR}/ceph:/etc/ceph \
-e CEPHFS_CREATE=1 \
--name mds1 \
ceph/daemon mds
```

透過以下指令檢查是否建立無誤：
```sh
$ docker exec -ti mds1 ceph mds stat
e5: 1/1/1 up {0=mds-aea2f53de13a=up:active}

$ docker exec -ti mds1 ceph fs ls
name: cephfs, metadata pool: cephfs_metadata, data pools: [cephfs_data ]
```
