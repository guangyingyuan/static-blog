---
catalog: true
title: Ceph FS 基本操作
date: 2015-11-21 17:08:54
categories:
- Ceph
tags:
- Ceph
- Storage
- File System
---
Ceph FS 底層的部分同樣是由 RADOS(OSDs + Monitors + MDSs) 提供，在上一層同樣與 librados 溝通，最上層則是有不同的 library 將其轉換成標準的 POSIX 檔案系統供使用。

![](/images/ceph/cephfs.png)

<!--more-->

## 建立一個 Ceph File System
首先將一個叢集建立完成，並提供 Metadata Server Node 與 Client，建立 Client 可以透過以下指令：
```sh
$ ceph-deploy install <myceph-client>
```

建立 MDS 節點可以透過以下指令：
```sh
$ ceph-deploy mds create mds-node
```

當 Ceph 叢集已經提供了MDS後，可以建立 Data Pool 與 Metadata Pool：
```sh
$ ceph osd pool create cephfs_data 128
$ ceph osd pool create cephfs_metadata 128
```
> **How to judge PG number**：
* Less than 5 OSDs set pg_num to 128
* Between 5 and 10 OSDs set pg_num to 512
* Between 10 and 50 OSDs set pg_num to 4096
* If you have more than 50 OSDs, you need to understand the tradeoffs and how to calculate the pg_num value by yourself

完成 Pool 建立後，我們將儲存池拿來給 File System 使用，並建立檔案系統：
```sh
$ ceph fs new cephfs cephfs_metadata cephfs_data
```

取得 Client 驗證金鑰：
```sh
$ cat /etc/ceph/ceph.client.admin.keyring
[client.admin]
	key = AQC/mo9VxqsXDBAAQ/LQtTmR+GTPs65KBsEPrw==
```

建立，並儲存到檔案`admin.secret`：
```sh
AQC/mo9VxqsXDBAAQ/LQtTmR+GTPs65KBsEPrw==
```

檢查 MDS 與 FS：
```sh
$ ceph fs ls
$ ceph mds stat
```

建立 Mount 用目錄，並且 Mount File System：
```sh
$ sudo mkdir /mnt/mycephfs
$ sudo mount -t ceph {ip-address-of-monitor}:6789:/ /mnt/mycephfs/ -o name=admin,secretfile=admin.secret
```

檢查系統 DF 與 Mount 結果：
```sh
$ sudo df -l
$ sudo mount
```
> 使用CEPH檔案系統時，要注意是否安裝了元資料伺服器(Metadata Server)。且請確認CEPH版本為是`0.84`之後的版本。

## Ceph Filesystem FUSE (File System in User Space)
首先在MDS節點上安裝ceph-fuse 套件：
```sh
$ sudo apt-get install -y ceph-fuse
```

完成後，我們就可以Mount起來使用：
```sh
$ sudo mkdir /mnt/myceph-fuse
$ sudo ceph-fuse -m {ip-address-of-monitor}:6789 /mnt/myceph-fuse
```

當 Mount 成功後，就可以到該目錄檢查檔案。

> **FUSE**：使用者空間檔案系統（Filesystem in Userspace，簡稱FUSE）是作業系統中的概念，指完全在使用者態實作的檔案系統。目前Linux通過內核模組對此進行支援。一些檔案系統如ZFS，glusterfs和lustre使用FUSE實作。
