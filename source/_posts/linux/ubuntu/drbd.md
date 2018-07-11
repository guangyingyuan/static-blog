---
title: DRBD 進行跨節點的區塊儲存備份
catalog: true
date: 2016-04-01 16:23:01
categories:
- Linux
tags:
- Linux
- Storage
---
DRBD（Distributed Replicated Block
Device）是一個分散式區塊裝置備份系統，DRBD 是由 Kernel 模組與相關腳本組成，被用來建置高可靠的叢集服務。實現方式是透過網路來 mirror 整個區塊裝置，一般可作為是網路 RAID 的一類。DRBD 允許使用者在遠端機器上建立一個 Local 區塊裝置的即時 mirror。

<!--more-->

### 安裝 DRBD
本教學將使用以下主機數量與角色：

|  IP Address  |   Role   |   Disk   |
|--------------|----------|----------|
| 172.16.1.184 |  master  | /dev/vdb |
| 172.16.1.182 |  backup  | /dev/vdb |

在 Ubuntu 14.04 LTS Server 可以直接透過`apt-get`來安裝 DRBD，指令如下：
```sh
$ sudo apt-get install linux-image-extra-virtual
$ sudo apt-get install -y drbd8-utils
```
> 完成後可以透過 lsmod 檢查：
> ```sh
> $ lsmod | grep drbd
>
> # 若沒有則使用以下指令
> $ sudo modprobe drbd
> ```
> P.S 若出現錯誤請重新啟動主機。

### DRBD 設定
首先在各兩個節點透過`fdisk`來建立分區：
```sh
$ fdisk /dev/vdb

Command (m for help): n
Partition type:
   p   primary (0 primary, 0 extended, 4 free)
   e   extended
Select (default p): p
Partition number (1-4, default 1): 1
First sector (2048-20971519, default 2048): 2048
Last sector, +sectors or +size{K,M,G} (2048-20971519, default 20971519):
Using default value 20971519

Command (m for help): w
```

之後建立`/etc/drbd.d/ha.res`設定檔，並加入以下內容：
```sh
resource ha {
  on drbd-master {
    device /dev/drbd0;
    disk /dev/vdb1;
    address 172.16.1.184:1166;
    meta-disk internal;
 }
 on drbd-backup {
    device /dev/drbd0;
    disk /dev/vdb1;
    address 172.16.1.182:1166;
    meta-disk internal;
  }
}
```

上面都設定完成後，到`master`接著透過`drbdadm`指令建立：
```sh
$ drbdadm create-md ha

Writing meta data...
md_offset 10736365568
al_offset 10736332800
bm_offset 10736005120

Found some data

 ==> This might destroy existing data! <==

Do you want to proceed?
[need to type 'yes' to confirm] yes

initializing activity log
NOT initializing bitmap
New drbd meta data block successfully created.
```

透過指令啟用：
```sh
$ drbdadm up ha
$ drbd-overview
0:ha/0  WFConnection Secondary/Unknown Inconsistent/DUnknown C r----s
```

設定某一節點為主節點：
```sh
$ drbdadm -- --force primary ha
$ drbd-overview
0:ha/0  WFConnection Primary/Unknown UpToDate/DUnknown C r----s
```

檢查是否有正確啟動：
```
$ cd /dev/drbd
$ ls
by-disk  by-res

$ ls -al by-disk/
total 0
drwxr-xr-x 2 root root 60 Mar 24 16:46 .
drwxr-xr-x 4 root root 80 Mar 24 16:46 ..
lrwxrwxrwx 1 root root 11 Mar 24 16:49 vdb1 -> ../../drbd0

$ ls -al by-res/ha/
lrwxrwxrwx 1 root root 11 Mar 24 16:49 by-res/ha -> ../../drbd0
```

若沒問題後，即可 mount 使用：
```sh
$ mount /dev/drbd0 /mnt/
```
> 若出現`mount: you must specify the filesystem type`的話，記得格式化：
> ```sh
> $ mkfs.ext4 /dev/drbd0
> ```

這時候再透過指令查詢，可以看到已成功同步：
```sh
$ drbd-overview
0:ha/0  WFConnection Primary/Unknown UpToDate/DUnknown C r----s /mnt ext4 9.8G 23M 9.2G 1%
```

接著到`backup`節點，執行類似上面做法：
```sh
$ drbdadm create-md ha
$ drbdadm up ha
$ drbd-overview
  0:ha/0  SyncTarget Secondary/Primary Inconsistent/UpToDate C r-----
	[========>...........] sync'ed: 47.1% (5420/10236)Mfinish: 0:02:10 speed: 42,600 (45,252) want: 0 K/se
```
