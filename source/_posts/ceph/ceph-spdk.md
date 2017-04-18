---
layout: default
title: Ceph 使用 SPDK 加速 NVMe SSD
date: 2016-12-03 17:08:54
categories:
- Ceph
tags:
- Ceph
- Storage
- Distribution System
- SPDK
---
[SPDK(Storage Performance Development Kit)](https://github.com/spdk/spdk) 是 Intel 釋出的儲存效能開發工具，主要提供一套撰寫高效能、可擴展與 User-mode 的儲存應用程式工具與函式庫，而中國公司 XSKY 藉由該開發套件來加速 Ceph 在 NVMe SSD 的效能。

<!--more-->

首先進入 root，並 clone 專案到 local：
```shell=
$ sudo su -
$ git clone http://github.com/ceph/ceph
$ cd ceph
```

編輯`CMakeLists.txt`檔案，修改以下內容：
```shell=
option(WITH_SPDK "Enable SPDK" ON)
```

接著安裝一些相依套件與函式庫：
```shell=
$ ./install-deps.sh
$ sudo apt-get install -y libpciaccess-dev
```

接著需要在環境安裝 DPDK 開發套件，首先進入 src 底下的 dpdk 目錄，編輯`config/common_linuxapp`檔案修改以下內容：
```shell=
CONFIG_RTE_BUILD_SHARED_LIB=
```

完成後建置與安裝 DPDK：
```shell=
$ make config T=x86_64-native-linuxapp-gcc
$ make && make install
```

接著回到 ceph root 目錄進行建構 Ceph 準備，透過以下指令進行：
```shell=
$ ./do_cmake.sh
....
-- Configuring done
-- Generating done
-- Build files have been written to: /root/ceph/build
+ cat
+ echo 40000
+ echo done.
done.
```

確認上面無誤後就可以進行 compile 包含 SPDK 的 Ceph：
```shell=
$ cd build
$ make -j2
```

完成後就可以執行 test cluster，首先建構 vstart 程式：
```shell=
$ make vstart
$ ../src/vstart.sh -d -n -x -l
$ ./bin/ceph -s
```
> 若要關閉則使用以下方式：
> ```shell=
> $ ../src/stop.sh
> ```
