---
title: Foreman 管理 Puppet
catalog: true
comments: true
date: 2016-02-14 12:23:01
categories:
- DevOps
tags:
- DevOps
- Automation Engine
- Puppet
---
Foreman 是一個 Puppet 的生命周期管理系統，類似 puppet-dashboard，通過它可以很直觀的查看 Puppet 所有客戶端的同步狀態與 facter 參數。

<!--more-->

## 事前準備
由於 foreman 是取決於 puppet 執行主機的組態管理，他需要部署一個 puppet master 與 agent 環境。下面的列表為在安裝之前需要備設定的項目：
* Root 權限：所有伺服器能夠使用`sudo`。
* 私人網路 DNS：Forward 與 reverse 的 DNS 必須被設定，可參考[How To Configure BIND as a Private Network DNS Server on Ubuntu 14.04](https://www.digitalocean.com/community/tutorials/how-to-configure-bind-as-a-private-network-dns-server-on-ubuntu-14-04)。
* 防火牆有開啟使用的 port： Puppet master 必須可以被存取`8140`埠口。

## 安裝 Foreman
安裝 Foreman 最簡單的方法是使用 Foreman 安裝程式。Foreman 安裝程式與配置必要的元件來執行 Foreman，包含以下內容：
* Foreman
* Puppet master and agent
* Apache Web Server with SSL and Passenger module

下載 Foreman 可以依照以下指令進行：
```sh
$ sudo sh -c 'echo "deb http://deb.theforeman.org/ trusty 1.5" > /etc/apt/sources.list.d/foreman.list'
$ sudo sh -c 'echo "deb http://deb.theforeman.org/ plugins 1.5" >> /etc/apt/sources.list.d/foreman.list'
$ wget -q http://deb.theforeman.org/pubkey.gpg -O- | sudo apt-key add -
$ sudo apt-get update && sudo apt-get install foreman-installer
```

安裝完成後，要執行 Foreman Installer 可以使用以下指令：
```sh
$ sudo foreman-installer
```

完成後會看到以下資訊：
```sh
  Success!
  * Foreman is running at https://puppet-master.com
      Default credentials are 'admin:changeme'
  * Foreman Proxy is running at https://puppet-master.com:8443
  * Puppetmaster is running at port 8140
  The full log is at /var/log/foreman-installer/foreman-installer.log
```

之後修改`puppet.conf`檔案，開啟`diff`選項：
```sh
$ sudo vim /etc/puppet/puppet.conf

show_diff = true
```

### 新增 Foreman Host 到 Foreman 資料庫
要新增 Host 可以使用以下指令：
```sh
$ sudo puppet agent --test
```
完成後登入 Web，並輸入`admin`/`changeme`。

### 驗證 Foreman
```sh
$ sudo puppet module install -i /etc/puppet/environments/production/modules puppetlabs/ntp

Notice: Preparing to install into /etc/puppet/environments/production/modules ...
Notice: Downloading from https://forge.puppetlabs.com ...
Notice: Installing -- do not interrupt ...
/etc/puppet/environments/production/modules
└─┬ puppetlabs-ntp (v4.1.2)
  └── puppetlabs-stdlib (v4.10.0)
```

## 參考資源
* [How To Use Foreman To Manage Puppet Nodes on Ubuntu 14.04](https://www.digitalocean.com/community/tutorials/how-to-use-foreman-to-manage-puppet-nodes-on-ubuntu-14-04)
