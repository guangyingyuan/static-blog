---
catalog: true
title: Using bluestore in Kraken
date: 2016-11-28 17:08:54
categories:
- Ceph
tags:
- Ceph
- Storage
- BlueStore
---
本篇說明如何安裝 Kraken 版本的 Ceph，並將 objectstore backend 修改成 Bluestore，過程包含建立 RBD 等操作。

<!--more-->

## 硬體規格說明
本安裝由於實體機器數量受到限制，故只進行一台 MON 與兩台 OSD，而 OSD 數量則總共兩顆，硬體規格如下所示：

| Role         | RAM   | CPUs   | Disk   | IP Address   |
|--------------|-------|--------|--------|--------------|
| mon1(deploy) | 4 GB  | 4 core | 500 GB | 172.16.1.200 |
| osd1         | 16 GB | 8 core | 2 TB   | 172.16.1.201 |
| osd2         | 16 GB | 8 core | 2 TB   | 172.16.1.202 |
| osd3         | 16 GB | 8 core | 2 TB   | 172.16.1.203 |

作業系統採用`Ubuntu 16.04 LTS Server`，Kernel 版本為`Linux 4.4.0-31-generic`。

## 事前準備
在開始部署 Ceph 叢集之前，我們需要在每個節點做一些基本的準備，來確保叢集安裝的過程是流暢的，本次安裝會擁有四台節點。

首先在每一台節點新增以下內容到`/etc/hosts`：
```
127.0.0.1	localhost

172.16.1.200 mon1
172.16.1.201 osd1
172.16.1.202 osd2
172.16.1.203 osd3
```

然後設定各節點 sudo 指令的權限，使之不用輸入密碼(若使用 root 則忽略)：
```sh
$ echo "ubuntu ALL = (root) NOPASSWD:ALL" | \
sudo tee /etc/sudoers.d/ubuntu && sudo chmod 440 /etc/sudoers.d/ubuntu
```

接著在設定`deploy`節點能夠以無密碼方式進行 SSH 登入其他節點，請依照以下執行：
```sh
$ ssh-keygen -t rsa
$ ssh-copy-id mon1
$ ssh-copy-id osd1
...
```
> 若不同節點之間使用不同 User 進行 SSH 部署的話，可以設定 ~/.ssh/config

之後在`deploy`節點安裝部署工具，首先使用 apt-get 來進行安裝基本相依套件，再透過 pypi 進行安裝 ceph-deploy 工具：
```sh
$ sudo apt-get install -y python-pip
$ sudo pip install -U ceph-deploy
```

## 節點部署
首先建立一個名稱為 local 的目錄，並進到目錄底下：
```sh
$ sudo mkdir local && cd local
```

接著透過 ceph-deploy 在各節點安裝 ceph：
```sh
$ ceph-deploy install --release kraken mon1 osd1 osd2 osd3
```

完成後建立 Monitor 節點資訊到 ceph.conf 中：
```sh
$ ceph-deploy new mon1 <other_mons>
```

接著編輯目錄底下的 ceph.conf，並加入以下內容：
```sh
[global]
...
rbd_default_features = 3

osd pool default size = 3
osd pool default min size = 1

public network = 172.16.1.0/24
cluster network = 172.16.1.0/24

filestore_xattr_use_omap = true
enable experimental unrecoverable data corrupting features = bluestore rocksdb
bluestore fsck on mount = true
bluestore block db size = 134217728
bluestore block wal size = 268435456
bluestore block size = 322122547200
osd objectstore = bluestore

[osd]
bluestore = true
```

若確認沒問題，即可透過以下指令初始化 mon：
```sh
$ ceph-deploy mon create-initial
```

上述沒有問題後，就可以開始部署實際作為儲存的 OSD 節點，我們可以透過以下指令進行：
```sh
$ ceph-deploy osd prepare --bluestore osd1:<device>
```

## 系統驗證
### 叢集檢查
首先要驗證環境是否有部署成功，可以透過 ceph 提供的基本指令做檢查：
```sh
$ ceph -v
ceph version v11.0.2 (697fe64f9f106252c49a2c4fe4d79aea29363be7)

$ ceph -s

    cluster 6da24ae5-755f-4077-bfa0-78681dfc6bde
     health HEALTH_OK
     monmap e1: 1 mons at {r-mon00=172.16.1.200:6789/0}
            election epoch 7, quorum 0 mon1
        mgr no daemons active
     osdmap e256: 3 osds: 3 up, 3 in
            flags sortbitwise,require_jewel_osds
      pgmap v920162: 128 pgs, 1 pools, 6091 MB data, 1580 objects
            12194 MB used, 588 GB / 600 GB avail
                 128 active+clean
```

另外也可以用 osd 指令來查看部屬的 osd 資訊：
```sh
$ ceph osd tree

ID WEIGHT  TYPE NAME        UP/DOWN REWEIGHT PRIMARY-AFFINITY
-1 0.58618 root default
-2 0.29309     host osd1
 0 0.29309         osd.0         up  1.00000          1.00000
-3 0.29309     host osd2
 1 0.29309         osd.1         up  1.00000          1.00000
-4 0.29309     host osd3
 1 0.29309         osd.2         up  1.00000          1.00000
```

### RBD 建立
本節說明在 Kraken 版本建立 RBD 來進行使用，在預設部署起來的叢集下會存在一個儲存池 rbd，因此可以省略建立新的儲存池。

首先透過以下指令建立一個區塊裝置映像檔：
```sh
$ rbd create rbd/bd -s 50G
```

接著透過 info 指令查看區塊裝置映像檔資訊：
```sh
$ rbd info rbd/bd

rbd image 'bd':
	size 51200 MB in 12800 objects
	order 22 (4096 kB objects)
	block_name_prefix: rbd_data.102d474b0dc51
	format: 2
	features: layering, striping
	flags:
	stripe unit: 4096 kB
	stripe count: 1
```
> P.S. 這邊由於 Kernel 版本問題有些特性無法支援，因此在 conf 檔只設定使用 layering, striping。

> P.S. 若預設未修改 feature 設定的話，可以透過以下指令修改:
```sh
$ rbd feature disable rbd/bd <feature_name>
```

> 以下為目前支援的特性：

> | 屬性名稱         | 說明                                   | Bit Code |
  |----------------|----------------------------------------|----------|
  | layering       | 支援分層                                | 1         |
  | striping       | 支援串連(v2)                            | 2         |
  | exclusive-lock | 支援互斥鎖定                             | 4         |
  | object-map     | 支援物件映射(相依於 exclusive-lock )      | 8         |
  | fast-diff      | 支援快速計算差異(相依於 object-map )       | 16        |
  | deep-flatten   | 支援快照扁平化操作                        | 32         |
  | journaling     | 支援紀錄 I/O 操作(相依於 exclusive-lock ) | 64         |

接著就可以透過 Linux mkfs 指令來格式化 rbd：
```sh
$ sudo mkfs.ext4 /dev/rbd0
$ sudo mount /dev/rbd0 /mnt
```

最後透過 dd 指令測試 rbd 寫入效能：
```sh
$ dd if=/dev/zero of=/mnt/test bs=4096 count=4000000

4000000+0 records in
4000000+0 records out
16384000000 bytes (16 GB) copied, 119.947 s, 137 MB/s
```

另外有些需求為了測試 feature，卻又礙於 Kernel 不支援等問題，而造成無法 Map 時，可以透過 rbd-nbd 來進行 Map，安裝跟使用方式如下：
```sh
$ sudo apt-get install -y rbd-nbd
$ sudo rbd-nbd map rbd/bd
/dev/nbd0
```
> P.S. 在新版的 ceph 已經有內建 rbd nbd，參考 [rbd - manage command](http://docs.ceph.com/docs/jewel/man/8/rbd/#commands)。

最後透過 dd 指令測試 nbd 寫入效能：
```sh
$ dd if=/dev/zero of=./mnt-nbd/test bs=4096 count=4000000

4000000+0 records in
4000000+0 records out
16384000000 bytes (16 GB) copied, 168.201 s, 97.4 MB/s
```
