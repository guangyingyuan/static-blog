---
title: 用 Bcache 來加速硬碟效能
layout: default
date: 2016-07-05 16:23:01
categories:
- Linux
tags:
- Linux
- SSD
- Storage
---
Bcache 是按照固態硬碟特性來設計的技術，只按擦除 Bucket 的大小進行分配，並使用 btree 和 journal 混合方法來追蹤快取資料，快取資料可以是 Bucket 上的任意一個 Sector。Bcache 最大程度上減少了隨機寫入的代價，它按循序的方式填充一個 Bucket，重新使用時只需將 Bucket 設置為無效即可。Bcache 也支援了類似 Flashcache 的快取策略，如write-back、write-through 與 write-around。

<!--more-->

## 安裝與設定
首先要先安裝 bcache-tools，這邊採用 ubuntu 的`apt-get`來進行安裝：
```sh
$ sudo add-apt-repository ppa:g2p/storage
$ sudo apt-get update
$ sudo apt-get install -y bcache-tools
```

完成安裝後，要準備一顆 SSD 與 HDD，並安裝於同一台主機上，如以下硬碟結構：
```sh
+-------+----------+       +--------+---------+       
| [ 固態硬碟(SSD)]  |       |  [ 傳統硬碟(HDD)]  |       
|  System   disk   +-------+  System   disk   +
|    (/dev/sdb)    |       |    (/dev/sdc)    |
+------------------+       +------------------+
```

當確認以上都沒問題後，即可用 bcache 指令來建立快取，首先建立後端儲存裝置：
```sh
$ sudo make-bcache -B /dev/sdc
UUID:			3b62c662-c739-4621-aca3-80efbf5e1da2
Set UUID:		67828232-2427-46d3-a473-e92e1f213f87
version:		1
block_size:		1
data_offset:		16
```
> * `-C`為快取層。
> * `-B`為 bcache 後端儲存層。
> * `--block` 為 Block Size，預設為 1k。
> * `--discard`為 SSD 上使用 TRIM。
> * `--writeback`為使用 writeback 模式，預設為 writethrough。
>
> P.S 如果有任何錯誤，請使用以下指令：
> ```sh
> $ sudo wipefs -a /dev/sdb
> ```

之後在透過指令建立快取儲存裝置，如以下：
```sh
$ sudo make-bcache --block 4k --bucket 2M -C /dev/sdb -B /dev/sdc --wipe-bcache
UUID:			192dfaf6-fd2a-4246-b4be-f159c3346850
Set UUID:		ed865522-96a7-43e5-8dab-e8c024fe85db
version:		0
nbuckets:		228946
block_size:		1
bucket_size:		1024
nr_in_set:		1
nr_this_dev:		0
first_bucket:		1
```

完成後，可以用`bcache-super-show`指令確認是否有建立，並取得 UUID：
```sh
$ sudo bcache-super-show /dev/sdb | grep cset.uuid
cset.uuid		b6295aac-34c3-4630-8872-9aa18618daea
```

也可以用其他指令查看儲存建立狀況：
```sh
$ lsblk
NAME      MAJ:MIN RM   SIZE RO TYPE MOUNTPOINT
sda         8:0    0 232.9G  0 disk
└─sda1      8:1    0 232.9G  0 part /
sdb         8:16   0 111.8G  0 disk
└─bcache0 251:0    0 465.8G  0 disk
sdc         8:32   0 465.8G  0 disk
└─bcache0 251:0    0 465.8G  0 disk
```

接著將快取儲存裝置附加到後端儲存裝置：
```sh
$ echo "<cset.uuid>" > /sys/block/bcache0/bcache/attach
```
> `bcache0`會隨建立的不同而改變。

之後可以依需求設定 cache mode，透過以下方式：
```sh
$ echo writeback > /sys/block/bcache0/bcache/cache_mode
```

一切完成後，可以透過以下方式來檢查 Cache 狀態：
```sh
$ cat /sys/block/bcache0/bcache/state
clean
```
> * `no cache`：表示沒有任何快取裝置連接到後台儲存裝置。
> * `clean`：表示快取已連接，且快取是乾淨的。
> * `dirty`：表示一切設定完成，但必須啟用 writeback，且快取不是乾淨的。
> * `inconsistent`：這表示後端是不被同步的高速快取儲存裝置。記得換爛一點。

## 測試寫入速度
這邊採用 Linux 的 dd 工具來看寫入速度：
```sh
$ dd if=/dev/zero of=/dev/bcache0 bs=1G count=1 oflag=direct
```
