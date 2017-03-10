---
title: 使用 HAProxy 進行負載平衡
layout: default
date: 2016-03-28 16:23:01
categories:
- Linux
tags:
- Linux
- Load Balancer
---
HAProxy 提供了高可靠性、負載平衡（Load Balancing）、基於 TCP 以及 HTTP 的應用程式代理，更支援了虛擬機的使用。HAProxy 是一個開放式原始碼，免費、快速以及非常可靠，根據官方測試結果，該軟體最高能夠支援到 10G 的並行傳輸，因此特別適合使用在負載很大的 Web 伺服器，且這些伺服器通常需要保持 Session 或者 Layer 7 網路的處理，但這些都可以使用 HAProxy 來完成。

HAProxy 具有以下幾個優點：
* 開放式原始碼，因此免費，且穩定性高
* 能夠負荷 10G 網路的並行傳輸
* 支援連線拒絕功能
* 支援全透明化的代理
* 擁有內建的監控狀態儀表板
* 支援虛擬機的使用

<!--more-->

### HAProxy 安裝
本教學會使用到一台 Proxy 節點與兩台 Web 節點，如下：

| IP Address  |   Role   |
|-------------|----------|
|  172.17.0.2 |  proxy   |
|  172.17.0.3 |  web-1   |
|  172.17.0.4 |  web-2   |

本篇採用 Ubuntu 作業系統，因此可透過 apt 直接安裝，以下範例是在 Ubuntu Server 環境中操作：
```sh
$ sudo apt-get install software-properties-common python-software-properties
$ sudo apt-add-repository ppa:vbernat/haproxy-1.5
$ sudo apt-get update
$ sudo apt-get install haproxy
```
> 若要安裝其他版本，可以修改成以下：
> ```sh
> sudo apt-add-repository ppa:vbernat/haproxy-1.6
> ```

### HAProxy 設定
完成安裝後，要透過編輯`/etc/haproxy/haproxy.cfg`設定檔來配置 Proxy：
```sh
global
	log /dev/log	local0
	log /dev/log	local1 notice
	chroot /var/lib/haproxy
	stats socket /run/haproxy/admin.sock mode 660 level admin
	stats timeout 30s
	user haproxy
	group haproxy
	daemon
        maxconn 1024

	ca-base /etc/ssl/certs
	crt-base /etc/ssl/private

	ssl-default-bind-ciphers ECDH+AESGCM:DH+AESGCM:ECDH+AES256:DH+AES256:ECDH+AES128:DH+AES:ECDH+3DES:DH+3DES:RSA+AESGCM:RSA+AES:RSA+3DES:!aNULL:!MD5:!DSS
	ssl-default-bind-options no-sslv3

defaults
	log	global
	mode	http
	option	httplog
	option	dontlognull
        timeout connect 5000
        timeout client  50000
        timeout server  50000
	errorfile 400 /etc/haproxy/errors/400.http
	errorfile 403 /etc/haproxy/errors/403.http
	errorfile 408 /etc/haproxy/errors/408.http
	errorfile 500 /etc/haproxy/errors/500.http
	errorfile 502 /etc/haproxy/errors/502.http
	errorfile 503 /etc/haproxy/errors/503.http
	errorfile 504 /etc/haproxy/errors/504.http

frontend nginxs_proxy
    bind 172.17.0.2:80
    mode http
    default_backend nginx_servers

backend nginx_servers
    mode http
    balance roundrobin
    option forwardfor
    http-request set-header X-Forwarded-Port %[dst_port]
    http-request add-header X-Forwarded-Proto https if { ssl_fc }
    option httpchk HEAD / HTTP/1.1\r\nHost:localhost
    server web1 172.17.0.3:80 check cookie s1
    server web2 172.17.0.4:80 check cookie s2

listen haproxy_stats
    bind 0.0.0.0:8080
    stats enable
    stats hide-version
    stats refresh 30s
    stats show-node
    stats auth username:password
    stats uri  /stats
```

完成設定後，需重啟服務：
```sh
$ sudo service haproxy restart
```
