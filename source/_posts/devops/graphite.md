---
title: 利用 Graphite 監控系統資料
catalog: true
comments: true
date: 2016-02-11 12:23:01
categories:
- DevOps
tags:
- DevOps
- Monitoring
- Data Collect
---
Graphite 是一款開源的監控繪圖工具。Graphite 可以實時收集、存儲、顯示時間序列類型的數據（time series data）。它主要有三個部分構成：
1. **Carbon**：基於 Twisted 的行程，用來接收資料。
2. **Whisper**：專門儲存時間序列類型資料的小型資料庫。
3. **Graphite** webapp：基於 Django 的網頁應用程式。

<!--more-->

## 安裝 Graphite
在開始配置 Graphite 之前，需要先安裝系統相依套件：
```sh
$ sudo apt-get install build-essential graphite-web graphite-carbon python-dev apache2 libapache2-mod-wsgi libpq-dev python-psycopg2
```
> 在安裝期間`graphite-carbon`會詢問是否要刪除 whisper database files，這邊回答`YES`。

### 配置 Carbon
透過增加`[test]`到 Carbon 的`/etc/carbon/storage-schemas.conf` 檔案，這部分單純用於測試使用，如果不需要可以直接跳過：
```txt
[carbon]
pattern = ^carbon\.
retentions = 60:90d

[test]
pattern = ^test\.
retentions = 5s:3h,1m:1d

[default_1min_for_1day]
pattern = .*
retentions = 60s:1d
```
> 更多如何配置 Carbon storage 的資訊，可以參考 [ storage-schemas.con](http://graphite.readthedocs.org/en/latest/config-carbon.html#storage-schemas-conf)。

之後複製預設的聚合組態到`/etc/carbon`：
```sh
$ sudo cp /usr/share/doc/graphite-carbon/examples/storage-aggregation.conf.example /etc/carbon/storage-aggregation.conf
```

設定在開機時，啟動 Carbon 快取，編輯`/etc/default/graphite-carbon`：
```sh
CARBON_CACHE_ENABLED=true
```

啟動 Carbon 服務：
```sh
$ sudo service carbon-cache start
```

### 安裝與配置 PostgreSQL
安裝 PostgreSQL 讓 graphite-web 應用程式使用：
```sh
$ sudo apt-get install postgresql
```

切換到`postgres`使用者，並建立資料庫使用者給 Graphite：
```txt
$ sudo su - postgres
postgres# createuser graphite --pwprompt
```

建立`graphite`與`grafana`資料庫：
```sh
postgres# createdb -O graphite graphite
postgres# createdb -O graphite grafana
```

切換`graphite`來檢查配置是否成功：
```sh
$ sudo su - graphite
```

### 設定 Graphite
更新 Graphite web 使用的後端資料庫與其他設定，編輯`/etc/graphite/local_settings.py`，加入以下：
```sh
DATABASES = {
'default': {
    'NAME': 'graphite',
    'ENGINE': 'django.db.backends.postgresql_psycopg2',
    'USER': 'graphite',
    'PASSWORD': 'graphiteuserpassword',
    'HOST': '127.0.0.1',
    'PORT': ''
    }
}

USE_REMOTE_USER_AUTHENTICATION = True
TIME_ZONE = 'UTC'
SECRET_KEY = 'some-secret-key'
```
> * `TIME_ZONE` 可以查詢 [Wikipedia’s timezone database](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones)
> * `SECRET_KEY`可以使用`openssl rand -hex 10`指令來建立。

初始化資料庫：
```sh
$ sudo graphite-manage syncdb
```

### 設定 Graphite 使用 Apache
首先複製 Graphite 的 Apache 配置樣板到 Apache sites-available 目錄：
```sh
$ sudo cp /usr/share/graphite-web/apache2-graphite.conf /etc/apache2/sites-available
```

編輯`/etc/apache2/sites-available/apache2-graphite.conf`，修改預設監聽的 port：
```
<VirtualHost *:8080>
```

編輯`/etc/apache2/ports.conf`加入監聽的 port：
```sh
Listen 80
Listen 8080
```

取消預設 Apache 的 site：
```sh
$ sudo a2dissite 000-default
```

啟用 Graphite 的虛擬 site，並重新載入：
```sh
$ sudo a2ensite apache2-graphite
$ sudo service apache2 reload
```

重新啟動 apache 服務：
```sh
$ sudo service apache2 restart
```
> 完成後，即可登入`example_domain.com:8080`。

測試一個簡單資料：
```sh
$ for i in 4 6 8 16 2; do echo "test.count $i `date +%s`" | nc -q0 127.0.0.1 2003; sleep 6; done
```

## 參考連結
* [Deploy Graphite with Grafana on Ubuntu 14.04](https://www.linode.com/docs/uptime/monitoring/deploy-graphite-with-grafana-on-ubuntu-14-04)
* [How To Install and Use Graphite on an Ubuntu 14.04 Server](https://www.digitalocean.com/community/tutorials/how-to-install-and-use-graphite-on-an-ubuntu-14-04-server)
* [Grafana＋collectd＋InfluxDB](http://www.vpsee.com/2015/03/a-modern-monitoring-system-built-with-grafana-collected-influxdb/)
