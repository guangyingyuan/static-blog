---
title: Ubuntu PXE 安裝與設定
layout: default
comments: true
date: 2015-11-05 12:23:01
categories:
- Linux
tags:
- Linux
- PXE
- Bare Metal
---
預啟動執行環境（Preboot eXecution Environment，PXE，也被稱為預執行環境)提供了一種使用網路介面（Network Interface）啟動電腦的機制。這種機制讓電腦的啟動可以不依賴本地資料儲存裝置（如硬碟）或本地已安裝的作業系統。

![PXE](/images/pxe.png)

<!--more-->


PXE 伺服器必須要提供至少含有 DHCP 以及 TFTP :
* DHCP 服務必須要能夠提供用戶端的網路參數之外，還得要告知用戶端 TFTP 所在的位置為何才行
* TFTP 則是提供用戶端 boot loader 及 kernel file 下載點的重要服務

## Kickstart
我們在手動安裝作業系統時，會針對需求安裝作業系統的相關套件、設定、disk切割等，當我們重複的輸入這些資訊時，隨著需安裝的電腦越多會越裝越阿雜，如果有人可以幫你完成這樣一套輸入資訊的話，就可以快速的自動化部署多台電腦，除了方便外，心情也格外爽快。

kickstart是Red Hat公司針對自動化安裝Red Had、Fedora、CentOS而制定的問題回覆規範，透過這個套件可以指定回覆設定問題，更能夠指定作業系統安裝其他套裝軟體，也可以執行Script(sh, bash)，通常kickstart設定檔(.cfg)是透過system-config-kickstart產生。也可以利用GUI的CentOS下產生安裝用的cfg檔案。

## Preseed
相對於kickstart，preseed是Debain/Ubuntu的自動化安裝回覆套件。

## 其他工具
* Stacki 3
* Ubuntu MAAS
* Foreman
* LinMin
* OpenStack Ironic
* Crowbar

## PXE 安裝與設定
首先安裝相關軟體，如 TFTP、DHCP等：
```sh
sudo apt-get install -y tftpd-hpa isc-dhcp-server lftp openbsd-inetd
```

### DHCP 設定
首先編輯 `/etc/dhcp/dhcpd.conf`檔案，在下面配置 DHCP：
```
ddns-update-style none;
default-lease-time 600;
max-lease-time 7200;
log-facility local7;

subnet 10.21.10.0 netmask 255.255.255.0 {
    range 10.21.10.200 10.21.10.250;
    option subnet-mask 255.255.255.0;
    option routers 10.21.10.254;
    option broadcast-address 10.21.10.255;
    filename "pxelinux.0";
    next-server 10.21.10.240;
}
```

完成後，重新啟動 DHCP 服務：
```sh
$ sudo service isc-dhcp-server restart

 * Stopping ISC DHCP server dhcpd [fail]
 * Starting ISC DHCP server dhcpd [ OK ]
```

檢查 DHCP 是否正確被啟動：
```sh
$ sudo netstat -lu | grep boot

udp        0      0 *:bootps                *:*
```

### TFTP Server 設定
編輯`/etc/inetd.conf`檔案，在最下面加入以下內容：
```
tftp dgram udp wait root /usr/sbin/in.tftpd  /usr/sbin/in.tftpd -s /var/lib/tftpboot
```

接著設定 Boot 時啟動服務，以及重新啟動相關服務：
```sh
$ sudo update-inetd --enable BOOT
$ sudo service openbsd-inetd restart

 * Restarting internet superserver inetd [ OK ]

$ sudo service tftpd-hpa restart
```

檢查 TFTP Server 是否正確啟動：
```sh
$ netstat -lu | grep tftp

udp        0      0 *:tftp                  *:*
```

### 建立開機選單
完成後安裝 syslinux:
```sh
sudo apt-get -y install syslinux
```

複製 syslinux 設定檔至`/var/lib/tftpboot`目錄中：
```sh
sudo cp /usr/lib/syslinux/menu.c32  /var/lib/tftpboot
sudo cp /usr/lib/syslinux/vesamenu.c32 /var/lib/tftpboot
sudo cp /usr/lib/syslinux/pxelinux.0 /var/lib/tftpboot
sudo cp /usr/lib/syslinux/memdisk /var/lib/tftpboot
sudo cp /usr/lib/syslinux/mboot.c32 /var/lib/tftpboot
sudo cp /usr/lib/syslinux/chain.c32 /var/lib/tftpboot
```

建立`/var/lib/tftpboot/pxelinux.cfg`目錄：
```sh
$ sudo mkdir /var/lib/tftpboot/pxelinux.cfg
```


接著編輯`/var/lib/tftpboot/pxelinux.cfg/default`檔案，設定開機選單，以下為簡單設定範例：
```
UI vesamenu.c32
TIMEOUT 100
MENU TITLE Welcom to KaiRen.Lab PXE Server System

LABEL local
  MENU LABEL Boot from local drive
  MENU DEFAULT
  localboot 0

LABEL Custom CentOS 6.5
  MENU LABEL Install Custom CentOS 6.5
  kernel ./centos/vmlinuz
  append initrd=./centos/initrd.img ksdevice=bootif ip=dhcp ks=http://10.21.10.240/centos-ks/default_ks.cfg

LABEL Hadoop CentOS 6.5
  MENU LABEL Install Hadoop CentOS 6.5
  kernel ./centos/vmlinuz
  append initrd=./centos/initrd.img ksdevice=bootif ip=dhcp ks=http://10.21.10.240/centos-ks/hdp_ks.cfg

LABEL Ubuntu Server 14.04
  MENU LABEL Install Ubuntu Server 14.04
  kernel ./ubuntu/server/14.04/linux
  append initrd=./ubuntu/server/14.04/initrd.gz method=http://10.21.10.240/ubuntu/server/14.04/
```
