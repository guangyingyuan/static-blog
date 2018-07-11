---
title: 用 Flashcache 建立高容量與高效能儲存
catalog: true
date: 2016-05-27 16:23:01
categories:
- Linux
tags:
- Linux
- SSD
- Storage
---
Flashcache 是 Facebook 的一個開源專案，主要被用於資料庫加速。基本結構為在硬碟（HDD）前面加了一層快取，即採用固態硬碟（SSD）裝置，把熱資料保存於快取中，寫入的過程也是先寫到 SSD，然後由 SSD 同步到傳統硬碟，最後的資料將保存於硬碟中，這樣可以不用擔心 SSD 損壞造成資料遺失問題，同時又可以有大容量、高效能的儲存。

<!--more-->

### 安裝
本教學採用 Ubuntu 14.04 LTS 進行安裝，並建立快取。首先安裝相依套件：
```sh
$ sudo apt-get install -y git build-essential dkms linux-headers-`uname -r`
```

完成後，透過 git 指令將專案下載至主機上：
```sh
$ git clone https://github.com/facebook/flashcache.git
$ cd flashcache
```

進入目錄編譯 flashcache 套件，並透過 make 進行安裝套件：
```sh
$ make
$ sudo make install
```

安裝完成後，就可以載入 flashcache 模組，透過以下指令：
```sh
$ sudo modprobe flashcache
```
> 若要檢查是否載入成功的話，可以使用以下指令：
```sh
$ dmesg | tail
[24181.921706] flashcache: module verification failed: signature and/or  required key missing - tainting kernel
[24181.922785] flashcache: flashcache-3.1.1 initialized
```

設定開機時自動載入模組：
```sh
$ echo "flashcache" | sudo tee -a /etc/modules
```

### 設定快取
首先準備一顆 SSD 與 HDD，並安裝於同一台主機上，如以下硬碟結構：
```sh
+-------+----------+       +--------+---------+       
| [ 固態硬碟(SSD)]  |       |  [ 傳統硬碟(HDD)]  |       
|  System   disk   +-------+  System   disk   +
|    (/dev/sdb)    |       |    (/dev/sdc)    |
+------------------+       +------------------+
```

在開始前，必須先將傳統硬碟進行格式化：
```sh
$ sudo mkfs.ext4 /dev/sdc
```

接著要初始化 Flashcache，然後透過 Flashcache 指令來設定快取：
```sh
$ sudo flashcache_create -p back -b 4k cachedev /dev/sdb /dev/sdc
cachedev cachedev, ssd_devname /dev/sdb, disk_devname /dev/sdc cache mode WRITE_BACK
block_size 8, md_block_size 8, cache_size 0
Flashcache metadata will use 614MB of your 7950MB main memory
```

完成後，就可以透過 mount 來使用快取：
```sh
$ sudo mount /dev/mapper/cachedev /mnt
```

若要在開機時自動 mount 為 Flashcache 的快取固態硬碟，可以在`rc.local`加入以下內容：
```sh
flashcache_load /dev/sdb
mount /dev/mapper/cachedev /mnt
```

若想監控 Flashcache 資訊的話，可以使用以下工具：
```sh
$ flashstat
```

最後，若想要刪除 Flashcache 的話，可以使用以下指令：
```sh
$ sudo umount /mnt
$ sudo flashcache_destroy /dev/sdb
$ sudo dmsetup remove cachedev
```

### fio 測試
這邊採用 fio 來進行測試，首先透過`apt-get`安裝套件：
```sh
$ sudo apt-get install fio
```

完成後，即可透過 fio 指令進行效能測試：
```sh
$ fio --filename=/dev/sdb --direct=1 \
--rw=randrw --ioengine=libaio --bs=4k \
--rwmixread=100 --iodepth=16 \
--numjobs=16 --runtime=60 \
--group_reporting --name=4ktest
```
> fio 測試工具 options 參數：
> * `--filename=/dev/sdb`：指定要測試的磁碟。
> * `--direct=1`：預設值為 0 ,必須設定為 1 才會測試到真實的 non-buffered I/O。
> * `--rw=randrw`：可以設定的參數如下 randrw 代表 random(隨機) 的 read(讀) write(寫),其他的請參考下面說明。
>  * **read** : Sequential reads. (循序讀)
>  * **write** : Sequential writes. (循序寫)
>  * **randread** : Random reads. (隨機讀)
>  * **randwrite** : Random writes. (隨機寫)
>  * **rw** : Mixed sequential reads and writes. (循序讀寫)
>  * **randrw** : Mixed random reads and writes. (隨機讀寫)
> * `--ioengine=libaio`：定義如何跑 I/O 的方式, libaio 是 Linux 本身非同步(asynchronous) I/O 的方式. 其他還有 sync , psync , vsync , posixaio , mmap , splice , syslet-rw , sg , null , net , netsplice , cpuio , guasi , external。
> * `--bs=4k`：bs 或是 blocksize ,也就是檔案寫入大小,預設值為 4K。
> * `--rwmixread=100`： 當設定為 Mixed ,同一時間 read 的比例為多少,預設為 50%。
> * `--refill_buffers`：refill_buffers 為預設值,應該是跟 I/O Buffer 有關 (refill the IO buffers on every submit),把 Buffer 填滿就不會跑到 Buffer 的值。
> * `--iodepth=16`：同一時間有多少 I/O 在做存取,越多不代表存儲裝置表現會更好,通常是 RAID 時須要設大一點。
> * `--numjobs=16`：跟前面的 iodepth 類似,但不一樣,在 Linux 下每一個 job 可以生出不同的 processes/threads ,numjobs 就是在同一個 workload 同時提出多個 I/O 請求,通常負載這個會比較大.預設值為 1。
> * `--runtime=60`：這一測試所需的時間,單位為 秒。
> * `--group_reporting`：如果 numjobs 有指定,設定 group_reporting 報告會以 per-group 的顯示方式。
> * `--name=4ktest`：代表這是一個新的測試 Job。

### 參考資料
* [Fio – Flexible I/O Tester](http://benjr.tw/34632)
* [Flashcache Wiki](https://github.com/facebook/flashcache/wiki/QuickStart-Recipe-for-Ubuntu-11.10)
* [Flashcache初次体验](http://navyaijm.blog.51cto.com/4647068/1567698)
* [Ubuntu bonnie++硬碟測速 (Linux 適用)](http://www.pupuliao.info/2013/12/ubuntu-bonnie%E7%A1%AC%E7%A2%9F%E6%B8%AC%E9%80%9F-linux-%E9%81%A9%E7%94%A8/)
