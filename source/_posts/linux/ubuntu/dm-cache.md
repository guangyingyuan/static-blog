---
title: DM-cache 建立混和區塊裝置
layout: default
date: 2016-04-21 16:23:01
categories:
- Linux
tags:
- Linux
- SSD
- Storage
---
DM-cache 是一種利用高速的儲存裝置給低速儲存裝置當作快取的技術，透過此一技術使儲存系統兼容容量與效能之間的平衡。DM-cache 目前是 Linunx 核心的一部份，透過裝置映射(Device Mapper)機制允許管理者建立混合的磁區(Volume)。

<!--more-->

## 快取建立流程
DM-cache 在比較新版本的 Linux Kernel 已經整合，以下為建置流程：
```sh
$ sudo blockdev --getsize64 /dev/sdb
250059350016

# ssd-metadata : 4194304 + (250059350016 * 16 / 262144) / 512 = 38001
# ssd-blocks :  250059350016 / 512 - 38001 = 488359166
$ sudo dmsetup create ssd-metadata --table '0 38001 linear /dev/sdb 0'
$ sudo dd if=/dev/zero of=/dev/mapper/ssd-metadata
$ sudo dmsetup create ssd-blocks --table '0 189008622 linear /dev/sdb 38001'

$ sudo blockdev --getsz /dev/sdc
1953525168

$ sudo dmsetup create home-cached --table '0 1953525168 cache /dev/mapper/ssd-metadata /dev/mapper/ssd-blocks /dev/sdc 512 1 writeback default 0'
$ ls -l /dev/mapper/home-cached

$ sudo mkdir /mnt/cache
$ sudo mount /dev/mapper/home-cached /mnt/cache
```
