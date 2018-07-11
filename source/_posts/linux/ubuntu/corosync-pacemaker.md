---
title: Pacemaker + Corosync 做服務 HA
catalog: true
date: 2016-5-26 16:23:01
categories:
- Linux
tags:
- Linux
- Load Balancer
- High Availability
---
Pacemaker 與 Corosync 是 Linux 中現今較常用的高可靠性叢集系統組合。Pacemaker 自身提供了很多常用的應用管理功能，不過若要使用 Pacemaker 來管理自己實作的服務，或是一些特別的東西時，就必須要自己實作管理資源。

<!---more-->

## 節點配置
本安裝將使用三台實體主機與一台虛擬機器，主機規格如以下所示：

|Role           |IP Address    |
|---------------|--------------|
|pacemaker1     | 172.16.35.10 |
|pacemaker2     | 172.16.35.11 |

> 作業系統皆為 `Ubuntu 14.04 Server`。

## 進行安裝與設定
首先要在所有節點之間設定無密碼 ssh 登入，透過以下方式：
```sh
$ ssh-keygen -t rsa
$ ssh-copy-id pacemaker1
```

安裝相關套件軟體：
```sh
$ sudo apt-get install -y corosync pacemaker heartbeat resource-agents fence-agents apache2
```

完成後，在`pacemaker1`進行以下步驟，首先編輯`/etc/corosync/corosync.conf`設定檔，修改一下內容：
```
# Please read the openais.conf.5 manual page

totem {
    version: 2

    # How long before declaring a token lost (ms)
    token: 3000

    # How many token retransmits before forming a new configuration
    token_retransmits_before_loss_const: 10

    # How long to wait for join messages in the membership protocol (ms)
    join: 60

    # How long to wait for consensus to be achieved before starting a new round of membership configuration (ms)
    consensus: 3600

    # Turn off the virtual synchrony filter
    vsftype: none

    # Number of messages that may be sent by one processor on receipt of the token
    max_messages: 20

    # Limit generated nodeids to 31-bits (positive signed integers)
    clear_node_high_bit: yes

    # Disable encryption
     secauth: off  #啟動認證功能

    # How many threads to use for encryption/decryption
     threads: 0

    # Optionally assign a fixed node id (integer)
    # nodeid: 1234

    # This specifies the mode of redundant ring, which may be none, active, or passive.
     rrp_mode: none

     interface {
        # The following values need to be set based on your environment
        ringnumber: 0
        bindnetaddr: 10.11.8.0  # 主機所在網路位址
        mcastaddr: 226.93.2.1  # 廣播地址，不要被佔用即可 P.S. 範圍:224.0.2.0～238.255.255.255
        mcastport: 5405  # 廣播埠口
    }
}

amf {
    mode: disabled
}

quorum {
    # Quorum for the Pacemaker Cluster Resource Manager
    provider: corosync_votequorum
    expected_votes: 1
}

aisexec {
        user:   root
        group:  root
}

logging {
        fileline: off
        to_stderr: yes  # 輸出到標準输出
        to_logfile: yes  # 輸出到日誌檔案
        logfile: /var/log/corosync.log  # 日誌檔案位置
        to_syslog: no  # 輸出到系统日誌
        syslog_facility: daemon
        debug: off
        timestamp: on
        logger_subsys {
                subsys: AMF
                debug: off
                tags: enter|leave|trace1|trace2|trace3|trace4|trace6
        }
}

# 新增 pacemaker 服務配置
service {
    ver: 1
    name: pacemaker
}
```

接著產生節點之間的溝通時的認證金鑰文件：
```sh
$ corosync-keygen -l
```

然後將設定檔與金鑰複製到`pacemaker2`上：
```sh
$ cd /etc/corosync/
$ scp -p corosync.conf authkey pacemaker2:/etc/corosync/
```

接著分別在`兩個`節點上編輯`/etc/default/corosync`檔案，修改以下：
```sh
# start corosync at boot [yes|no]
START=yes
```

接著將 Corosync 與 Pacemaker 服務啟動：
```sh
$ sudo service corosync start
$ sudo service pacemaker start
```

完成後透過 crm 指令來查看狀態：
```sh
$ crm status

Last updated: Tue Dec 27 03:12:07 2016
Last change: Tue Dec 27 02:35:18 2016 via cibadmin on pacemaker1
Stack: corosync
Current DC: pacemaker1 (739255050) - partition with quorum
Version: 1.1.10-42f2063
2 Nodes configured
0 Resources configured


Online: [ pacemaker1 pacemaker2 ]
```

關閉 corosync 預設啟動的 stonith 與 quorum 在兩台節點之問題：
```sh
$ crm configure property stonith-enabled=false
$ crm configure property no-quorum-policy=ignore
```

完成後，透過指令檢查：
```sh
$ crm configure show

node $id="739255050" pacemaker1
node $id="739255051" pacemaker2
property $id="cib-bootstrap-options" \
	dc-version="1.1.10-42f2063" \
	cluster-infrastructure="corosync" \
	stonith-enabled="false" \
	no-quorum-policy="ignore"
```

## 設定資源
Corosync 支援了多種資源代理，如 heartbeat、LSB(Linux Standard Base)與 OCF(Open Cluster Framework) 等。而 Corosync 也可以透過指令來查詢：
```sh
$ crm ra classes

lsb
ocf / heartbeat pacemaker redhat
service
stonith
upstart
```
> 而更細部的資訊可以透過以下查詢：
```sh
$ crm ra list lsb
$ crm ra list ocf heartbeat
$ crm ra info ocf:heartbeat:IPaddr
```

首先新增一個 heartbeat 資源：
```shell
$ crm configure
# 設定 VIP
crm(live)configure# primitive vip ocf:heartbeat:IPaddr params ip=172.16.35.20 nic=eth2 cidr_netmask=24 op monitor interval=10s timeout=20s on-fail=restart

# 設定 httpd
crm(live)configure# primitive httpd lsb:apache2
crm(live)configure# exit
There are changes pending. Do you want to commit them? yes
```

設定 Group 來將 httpd 與 vip 資源放一起：
```sh
crm(live)configure# group webservice vip httpd
```

完成後，透過 crm 指令查詢狀態：
```sh
$ crm status

Last updated: Tue Dec 27 03:52:21 2016
Last change: Tue Dec 27 03:52:20 2016 via cibadmin on pacemaker1
Stack: corosync
Current DC: pacemaker1 (739255050) - partition with quorum
Version: 1.1.10-42f2063
2 Nodes configured
2 Resources configured


Online: [ pacemaker1 pacemaker2 ]

 Resource Group: webservice
     vip	(ocf::heartbeat:IPaddr):	Started pacemaker1
     httpd	(lsb:apache2):	Started pacemaker2
```

最後就可以在`pacemaker1`或`pacemaker2`關閉服務來確認是否正常執行。
