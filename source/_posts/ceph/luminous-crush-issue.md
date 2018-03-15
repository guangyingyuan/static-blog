---
layout: default
title: Ceph Luminous CRUSH map 400000000000000 問題
date: 2018-2-11 17:08:54
categories:
- Ceph
tags:
- Ceph
- Storage
---
在 Ceph Luminous(v12) 版本中，預設開啟了一些 Kernel 特性，其中首先遇到的一般是 400000000000000 問題，即`CEPH_FEATURE_NEW_OSDOPREPLY_ENCODING`特性(可以從對照表得知[CEPH_FEATURE Table and Kernel Version](http://cephnotes.ksperis.com/blog/2014/01/21/feature-set-mismatch-error-on-ceph-kernel-client/))，剛問題需要在 Kernel 4.5+ 才能夠被支援，但如果不想升級可以依據本篇方式解決。

<!--more-->

在 L 版本中，當建立 RBD 並且想要 Map 時，會發生 timeout 問題，這時候可以透過 journalctl 來查看問題，如以下：
```sh
$ journalctl -xe
Feb 12 08:36:57 kube-server2 kernel: libceph: mon0 172.22.132.51:6789 feature set mismatch, my 106b84a842a42 < server's 40106b84a842a42, missing 400000000000000
```

查詢發現是 400000000000000 問題，這時可以選擇兩個解決方式：
* 將作業系統更新到 Linux kernel v4.5+ 的版本。
* 修改 CRUSH 中的 tunables 參數。

若想修改 CRUSH tunnables 參數，可以先到任一 Monitor 或者 Admin 節點中，執行以下指令：
```sh
$ ceph osd crush tunables jewel
$ ceph osd crush reweight-all
```

只要執行以上指令即可。
