---
title: 簡單設定 Apache2 Proxy 與 VirtualHost
date: 2015-11-04 17:08:54
catalog: true
categories:
- Linux
tags:
- Linux
- HTTP Server
---
Apache2 是一套經過測試與用於生產環境的 HTTP 伺服器，在許多網頁伺服器中被廣泛的採用，Apache2 除了本身能力強大外，其也整合了許多的額外模組來提供更多的擴展功能。

<!--more-->

## Apache2 安裝與設定
要安裝 Apache 伺服器很簡單，只需要透過 APT 進行安裝即可：
```sh
$ sudo apt-get update
$ sudo apt-get install -y libapache2-mod-proxy-html libxml2-dev apache2 build-essential
```

### 啟用 Proxy Modules
這邊可以透過以下指令來逐一啟動模組：
```sh
a2enmod proxy
a2enmod proxy_http
a2enmod proxy_ajp
a2enmod rewrite
a2enmod deflate
a2enmod headers
a2enmod proxy_balancer
a2enmod proxy_connect
a2enmod proxy_html
```

### 設定 Default conf 來啟用
編輯`/etc/apache2/sites-available/000-default.conf`設定檔，加入 Proxy 與 VirtualHost 資訊：
```sh
# 簡單 Proxypass 範例
<VirtualHost *:80>
        ErrorLog ${APACHE_LOG_DIR}/laravel-error.log
        CustomLog ${APACHE_LOG_DIR}/laravel-access.log combined
        ProxyPass / http://192.168.20.10/
        ProxyPassReverse / http://192.168.20.10/
        ProxyPreserveHost On
        ServerName laravel.kairen.com
        ServerAlias laravel.kairen.com
        ServerAlias *.laravel.kairen.com
</VirtualHost>

# 簡單 Load balancer 範例
<Proxy balancer://api-gateways>
    # Server 1
    BalancerMember http://192.168.20.11:8080/
    # Server 2
    BalancerMember http://192.168.20.12:8080/
</Proxy>

<VirtualHost *:*>
    ProxyPass / balancer://api-gateways
</VirtualHost>
```

完成後重新啟動服務即可：
```sh
$ sudo service apache2 restart
```

### 使用 SSL Reverse-Proxy
如果需要設定 SSL 連線與認證的話，可以透過以下設定方式來提供：
```
Listen 443
NameVirtualHost *:443
<VirtualHost *:443>
    SSLEngine On
    SSLCertificateFile /etc/apache2/ssl/file.pem
    ProxyPass / http://192.168.20.11:8080/
    ProxyPassReverse / http://192.168.20.11:8080/
</VirtualHost>
```

完成後重新啟動服務即可：
```sh
$ sudo service apache2 restart
```
