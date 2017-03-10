---
title: 利用 Keepalived 提供 VIP
layout: default
comments: true
date: 2016-03-28 12:23:01
categories:
- Linux
tags:
- Linux
- Load Balancer
---
# 簡介
Keepalived 是一種基於 VRRP 協定實現的高可靠 Web 服務方案，用於防止單點故障問題。因此一個 Web 服務運作至少會擁有兩台伺服器執行 Keepalived，一台作為 master，一台作為 backup，並提供一個虛擬 IP（VIP），master 會定期發送特定訊息給 backup 伺服器，當 backup 沒收到 master 訊息時，表示 master 已故障，這時候 backup 會接管 VIP，繼續提供服務，來確保服務的高可靠性。

<!--more-->

### VRRP
VRRP（Virtual Router Redundancy Protocol，虛擬路由器備援協定），是一個提供備援路由器來解決單點故障問題的協定，該協定有兩個重要概念：
* **VRRP 路由器與虛擬路由器**：VRRP 路由器是表示運作 VRRP 的路由器，是一個實體裝置，而虛擬路由器是指由 VRRP 建立的邏輯路由器。一組 VRRP 路由器協同運作，並一起構成一台虛擬路由器，該虛擬路由對外提供一個唯一固定的 IP 與 MAC 位址的邏輯路由器。

* **主控制路由器（master）與備援路由器（backup）**：主要是在一組 VRRP 中的兩種互斥角色。一個 VRRP 群組中只能擁有一台是 master，但可以有多個 backup 路由器。

VRRP 協定使用選擇策略從路由器群組挑選一台作為 master 來負責 ARP 與轉送 IP 封包，群組中其他路由器則作為 backup 的角色處理等待狀態。當由於某種原因造成 master 故障時，backup 會在幾秒內成為 master 繼續提供服務，該階段不用改變任何 IP 與 MAC 位址。

### Keepalived 節點配置
本教學將使用以下主機數量與角色：

|  IP Address  |   Role   |
|--------------|----------|
| 172.16.1.101 |   vip    |
| 172.16.1.102 |  master  |
| 172.16.1.103 |  backup  |

### 安裝與設定
這 ubuntu 14.04 LTS Server 中已經內建了 Keepalived 可以透過 apt-get 來安裝：
```sh
$ sudo apt-get install -y keepalived
```

> 也可以透過 source code 進行安裝，流程如下：
```sh
$ sudo apt-get install build-essential libssl-dev
$ wget http://www.keepalived.org/software/keepalived-1.2.2.tar.gz
$ tar -zxvf keepalived-1.2.2.tar.gz
$ cd keepalived-1.2.2
$ ./configure --prefix=/usr/local/keepalived
$ make && make install
```

完成後，要將需要的設定檔進行複製到`/etc/`:
```
$ cp /usr/local/keepalived/etc/rc.d/init.d/keepalived /etc/init.d/keepalived
$ cp /usr/local/keepalived/sbin/keepalived /usr/sbin/
$ cp /usr/local/keepalived/etc/sysconfig/keepalived /etc/sysconfig/
$ mkdir -p /etc/keepalived/
$ cp /usr/local/etc/keepalived/keepalived.conf /etc/keepalived/keepalived.conf
```

安裝完成後編輯`/etc/keepalived/keepalived.conf`檔案進行設定，在`master`節點加入以下內容：
```sh
global_defs {
   notification_email {
      user@example.com
   }

   notification_email_from mail@example.org
   smtp_server 172.16.1.100
   smtp_connect_timeout 30
   router_id LVS_DEVEL
}

vrrp_instance VI_1 {
    state MASTER # Tag 為 MASTER
    interface eth0
    virtual_router_id 51
    priority 101   # MASTER 權重高於 BACKUP
    advert_int 1
    mcast_src_ip 172.16.1.102 # VRRP 實體主機的 IP

    authentication {
        auth_type PASS # Master 驗證方式
        auth_pass 1111
    }

    #VIP
    virtual_ipaddress {
        172.16.1.101 # 虛擬 IP
    }
}
```

Master 完成後，接著編輯`backup`節點的`/etc/keepalived/keepalived.conf`，加入以下內容：
```sh
global_defs {
   notification_email {
       user@example.com
   }

   notification_email_from mail@example.org
   smtp_server 172.16.1.100
   smtp_connect_timeout 30
   router_id LVS_DEVEL
}

vrrp_instance VI_1 {

    state BACKUP # Tag 為 BACKUP
    interface eth0
    virtual_router_id 51
    priority 100  # 權重要低於 MASTER
    advert_int 1
    mcast_src_ip 172.16.1.103 # vrrp 實體主機 IP

    authentication {
        auth_type PASS
        auth_pass 1111
    }

    # VIP
    virtual_ipaddress {
        172.16.1.101 # 提供的 VIP
    }
}
```
