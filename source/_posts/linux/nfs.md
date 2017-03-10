---
title: NFS 簡單安裝與使用
layout: default
comments: true
date: 2016-02-04 12:23:01
categories:
- Linux
tags:
- Linux
- File System
- Storage
- OpenStack
---
網路檔案系統(Network FileSystem，NFS)是早期由 SUN 公司所開發出來的`分散式檔案系統`協定。主要透過 RPC Service 使檔案能夠共享於網路中，NFS 的好處是它支援了不同系統與機器的溝通能力，使資料能夠很輕易透過網路共享給別人。

<!--more-->

## 安裝與設定
首先在 NFS 節點安裝以下套件：
```sh
$ sudo apt-get -y install nfs-kernel-server
```

編輯`/etc/idmapd.conf`設定檔，然後設定 Domain：
```
Domain = kyle.bai.example
```

接著編輯`/etc/exports`檔案，加入以下內容：
```sh
/var/nfs/images 10.0.0.0/24(rw,sync,no_root_squash,no_subtree_check)
/var/nfs/vms 10.0.0.0/24(rw,sync,no_root_squash,no_subtree_check)
/var/nfs/volumes 10.0.0.0/24(rw,sync,no_root_squash,no_subtree_check)
```

然後重新啟動 NFS Server，如以下指令：
```sh
$ sudo /etc/init.d/nfs-kernel-server restart
```

接著到 Client 端，安裝 NFS 工具：
```sh
$ sudo apt-get -y install nfs-common
```

編輯`/etc/idmapd.conf`設定檔，然後設定 Domain：
```
Domain = kyle.bai.example
```

然後透過以下指令來掛載使用：
```sh
$ sudo mount -t nfs kyle.bai.example:/var/nfs/images /var/nfs/images
```

完成後，透過以下指令來檢查：
```sh
$ df -hT
Filesystem                Type      Size  Used Avail Use% Mounted on
udev                      devtmpfs  7.9G  8.0K  7.9G   1% /dev
tmpfs                     tmpfs     1.6G  776K  1.6G   1% /run
/dev/sda1                 ext4      459G  8.3G  427G   2% /
none                      tmpfs     4.0K     0  4.0K   0% /sys/fs/cgroup
none                      tmpfs     5.0M     0  5.0M   0% /run/lock
none                      tmpfs     7.9G     0  7.9G   0% /run/shm
none                      tmpfs     100M     0  100M   0% /run/user
10.0.0.61:/var/nfs/images nfs4      230G  5.1G  213G   3% /var/nfs/images
```

編輯`/etc/fstab`檔案來提供開機掛載：
```
10.0.0.61:/var/nfs/vms /var/lib/nova/instances nfs defaults 0 0
```

也可以安裝自動掛載工具，透過以下指令安裝：
```sh
$ sudo apt-get -y install autofs
```

編輯`/etc/auto.master`檔案，加入以下內容到最後面：
```
/-    /etc/auto.mount
```

然後編輯`/etc/auto.mount`檔案，設定以下內容：
```sh
# create new : [mount point] [option] [location]
 /mntdir -fstype=nfs,rw  kyle.bai.example:/home
```

建立掛載用目錄：
```sh
$ sudo mkdir /mntdir
```

啟動 auto-mount 服務：
```sh
$ sudo initctl restart autofs
```

完成後透過以下方式檢查：
```sh
$ cat /proc/mounts | grep mntdir
```

## Cinder 使用 NFS
OpenStack Cinder 也支援了 NFS 的驅動，因此只需要在`/etc/cinder/cinder.conf`設定以下即可：
```
[DEFAULT]
...
enabled_backends = nfs

[nfs]
nfs_shares_config = /etc/cinder/nfs_shares
volume_driver = cinder.volume.drivers.nfs.NfsDriver
volume_backend_name = nfs-backend
nfs_sparsed_volumes = True
```

建立 Cinder backend 來提供不同的 Backend 的使用：
```
$ cinder type-create TYPE
$ cinder type-key TYPE set volume_backend_name=BACKEND
```
