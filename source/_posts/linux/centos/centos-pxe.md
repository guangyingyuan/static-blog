---
title: CentOS 6.5 PXE 安裝與設定
layout: default
comments: true
date: 2015-10-03 12:23:01
categories:
- Linux
tags:
- Linux
- PXE
- Bare Metal
---
預啟動執行環境（Preboot eXecution Environment，PXE，也被稱為預執行環境)提供了一種使用網路介面（Network Interface）啟動電腦的機制。這種機制讓電腦的啟動可以不依賴本地資料儲存裝置（如硬碟）或本地已安裝的作業系統。

<!--more-->

## 安裝環境
* CentOS 6.5 Minimal Install
* Intel(R) Core(TM)2 Quad CPU Q8400  @ 2.66GHz
* 500 GB
* 4G RAM
* Two Eth Card
 * Inner eth = PEX DHCP
 * Outer eth = Public network

## PXE 安裝與設定
首先安装 Setuptool 於 CentOS 上
```sh
$ sudo yum install -y setuptool ntsysv iptables system-config-network-tui
```

關閉防火牆與 SElinux，避免驗證時被阻擋：
```sh
$ sudo service iptables stop
$ sudo setenforce 0
```

接著編輯`/etc/selinux/config`，修改以下內容:
```
SELINUX=disabled
```

然後編輯`/etc/sysconfig/network-scripts/ifcfg-ethx`設定與確認 IP Address 是否正確：
```sh
DEVICE=ethx
HWADDR=C4:6E:1F:04:60:24    #依照個人eth
TYPE=Ethernet
UUID=ada7e5dc-a2e9-4a89-9c93-e1f559cd05f2
ONBOOT=yes
NM_CONTROLLED=yes
BOOTPROTO=none
IPADDR=192.168.28.130       #依照網路
NETMASK=255.255.255.0
USERCTL=no
```

## DHCP Server 安裝與設定
DHCP是「 動態主機配置協定」(Dynamic Host Configuration Protocol)。
DHCP是可自動將IP位址指派給登入TCP/IP網路的用戶端的一種軟體(這種IP位址稱為「動態IP位址」)。這邊安裝方式為以下：
```sh
$ sudo yum -y install dhcp
```

完成後編輯`/etc/dhcp/dhcpd.conf`，並修改以下設定:
```
ddns-update-style none;
ignore client-updates;
allow booting;
allow bootp;
option ip-forwarding false;
option mask-supplier false;
option broadcast-address 192.168.28.255;

subnet 192.168.28.0 netmask 255.255.255.0 {
        option routers 192.168.28.130
        range 192.168.28.50 192.168.28.60;
        #option subnet-mask 255.255.255.0;
        #option domain-name "i4502.dic.ksu";
        option domain-name-servers 10.21.20.1;

        next-server 192.168.28.130;
        filename        "pxelinux.0";
}
```

設定完後，重新啟動 DHCP 服務：
```sh
$ sudo service dhcpd start
$ sudo chkconfig dhcpd on
```

## TFTP Server 安裝與設定
簡單文件傳輸協議或稱小型文件傳輸協議（英文：Trivial File Transfer Protocol，縮寫TFTP），是一種簡化的文件傳輸協議。小型文件傳輸協議非常簡單，通過少量存儲器就能輕鬆實現——這在當時是很重要的考慮因素。所以TFTP被用於引導計算機，例如沒有大容量存儲器的路由器。安裝方式為以下：
```sh
$ sudo yum -y install tftp-server tftp
```

安裝完成後編輯`/etc/xinetd.d/tftp`，修改以下內容：
```
service tftp
{
        socket_type             = dgram
        protocol                = udp
        wait                    = yes
        user                    = root
        server                  = /usr/sbin/in.tftpd
        server_args             = -s /install/tftpboot
        disable                 = yes
        per_source              = 11
        cps                     = 100 2
        flags                   = IPv4
}
```
P.S 如果不修改 server_args，預設為 `/var/lib/tftpboot/`。

接著建立`/install/tftpboot`來存放 Boot 映像檔：
```sh
sudo mkdir -p /install/tftpboot
sudochcon --reference /var /install

sudo service xinetd restart
sudo chkconfig xinetd on
sudo chkconfig tftp on
```

## 安裝 syslinu
如果要使用 PXE 的開機管理程式與開機選單的話，那就得要安裝 CentOS 內建提供的 syslinux 軟體，從裡面撈出兩個檔案即可。當然啦，這兩個檔案得要放置在 TFTP 的根目錄下才好！整個實作的過程如下。
```sh
yum -y install syslinux
cp /usr/share/syslinux/menu.c32 /install/tftpboot/
cp /usr/share/syslinux/vesamenu.c32 /install/tftpboot/
cp /usr/share/syslinux/pxelinux.0 /install/tftpboot/
mkdir /install/tftpboot/pxelinux.cfg
ll /install/tftpboot/
```

## 掛載CentOS 映像檔
已CentOS 6.5 Minimal為範例。
```sh
mount -o loop CentOS-6.5-x86_64-minimal.iso /mnt
mkdir -p /install/tftpboot/kernel/centos6.5

cp /mnt/isolinux/vmlinuz /install/tftpboot/kernel/centos6.5
cp /mnt/isolinux/initrd.img /install/tftpboot/kernel/centos6.5
cp /mnt/isolinux/isolinux.cfg /install/tftpboot/pxelinux.cfg/demo
umount /mnt
```

* vmlinuz：就是安裝軟體的核心檔案 (kernel file)
* initrd.img：就是開機過程中所需要的核心模組參數
* isolinux.cfg --> demo：作為未來 PXE 所需要的開機選單之參考

## 設定開機選單
```sh
vim /install/tftpboot/pxelinux.cfg/default
```

**修改：**
```sh
UI vesamenu.c32
TIMEOUT 300
DISPLAY ./boot.msg
MENU TITLE Welcome to KAIREN's PXE Server System

LABEL local
  MENU LABEL Boot from local drive
  MENU DEFAULT
  localboot 0

LABEL ubuntu
  MENU LABEL Install CentOS 6.5
  kernel ./kernel/centos6.5/vmlinuz
  append initrd=./kernel/centos6.5/initrd.img
```

### 修改額外開機選單訊息
```sh
vim /install/tftpboot/boot.msg
```

**訊息：**
```sh
Welcome to KAI-REN's PXE Server System.

The 1st menu can let you system goto hard disk menu.
The 2nd menu can goto interactive installation step.
```

## 提供NFS Server 提供映像檔
NFS 就是 Network FileSystem 的縮寫，最早之前是由 Sun 這家公司所發展出來的。 它最大的功能就是可以透過網路，讓不同的機器、不同的作業系統、可以彼此分享個別的檔案 (share files)。這個 NFS 伺服器可以讓你的 PC 來將網路遠端的 NFS 伺服器分享的目錄，掛載到本地端的機器當中， 在本地端的機器看起來，那個遠端主機的目錄就好像是自己的一個磁碟分割槽一樣 (partition)。
```sh
mkdir -p /install/nfs_share/centos6.5
vim /etc/fstab
```

**在最底下加入：**
```sh
/root/CentOS-6.5-x86_64-minimal.iso /install/nfs_share/centos6.5 iso9660 defaults,loop 0 0
```

**安裝並提供分享目錄**
```sh
mount -a
df

yum -y install nfs-utils
vim /etc/exports
```

**加入：**
```sh
/install/nfs_share/  192.168.28.0/24(ro,async,nohide,crossmnt)  localhost(ro,async,nohide,crossmnt)
```

**修改System nfs conf**
```sh
vim /etc/sysconfig/nfs
```

**如下(P.S 找到上面這幾個設定值，我們得要設定好固定的 port 來開放防火牆給用戶處理)：**
```sh
RQUOTAD_PORT=901
LOCKD_TCPPORT=902
LOCKD_UDPPORT=902
MOUNTD_PORT=903
STATD_PORT=904
```

**修改NFS 不需要對映帳號**
```sh
vim /etc/idmapd.conf
```

**如下：**
```sh
[General]
Domain = "kairen.pxe.com"
[Mapping]
Nobody-User = nfsnobody
Nobody-Group = nfsnobody
```

**重開服務**
```sh
service rpcbind restart
service nfs restart
service rpcidmapd restart
service nfslock restart

chkconfig rpcbind on
chkconfig nfs on
chkconfig rpcidmapd on
chkconfig nfslock on
rpcinfo -p

showmount -e localhost
```
如果看到**Export list for localhost:
/install/nfs_share 192.168.28.0/24,localhost**就是成功了。

## 提供 HTTP Server
Apache HTTP Server（簡稱Apache）是Apache軟體基金會的一個開放原始碼的網頁伺服器軟體，可以在大多數電腦作業系統中運行，由於其跨平台和安全性。

```sh
yum -y install httpd
service httpd start
chkconfig httpd on
```

**建立CentOS 6.5目錄**
```sh
mkdir -p /var/www/html/install/centos6.5
vim /etc/fstab
```

**加入到最下方：**
```sh
/root/CentOS-6.5-x86_64-minimal.iso /var/www/html/install/centos6.5 iso9660 defaults,loop 0 0
```

**掛載起來**
```sh
mount -a
df
```

## 提供 FTP Server
```sh
yum -y install vsftpd
service vsftpd start
chkconfig vsftpd on

mkdir -p /var/ftp/install/centos6.5
vim /etc/fstab
```

**一樣加入Mount :**
```sh
/root/CentOS-6.5-x86_64-minimal.iso /var/ftp/install/centos6.5 iso9660 defaults,loop,context=system_u:object_r:public_content_t:s0 0 0
```

**掛載起來**
```sh
mount -a
df
```

* [HTTP](http://192.168.28.130/install/centos6.5)
* [FTP](ftp://192.168.28.130/install/centos6.5)
