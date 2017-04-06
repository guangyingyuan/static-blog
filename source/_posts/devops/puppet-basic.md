---
title: Puppet 介紹與使用
layout: default
comments: true
date: 2016-02-13 12:23:01
categories:
- DevOps
tags:
- DevOps
- Automation Engine
---
Puppet 是一個開放原始碼專案，基於 Ruby 的系統組態管理工具，採用 Client/Server 的部署架構。是一個為了實現資料中心自動化管理，而被設計的組態管理軟體，它使用跨平台語言規範，管理組態檔案、使用者、軟體套件與系統服務等。用戶端預設每個半小時會與伺服器溝通一次，來確定是否有更新。當然也可以配置主動觸發來強制用戶端更新。這樣可以把平常的系統管理工作程式碼化，透過程式碼化的好處是可以分享、保存與避免重複勞動，也可以快速恢復以及快速的大規模環境部署伺服器。

<center>![puppet-dataflow.png](/images/devops/puppet-dataflow.png)</center>

**優點：**
* 成熟的組態管理軟體。
* 應用廣泛。
* 功能很完善。
* 提供許多資源可以配置
* 擁有許多的支持者。

**缺點：**
* 無法批次處理。
* 語言採用 DSL 與 Ruby。
* 缺少錯誤回報與檢查。
* 要透過程式定義先後順序。

<!--more-->
## 基本概念介紹
### 基礎設施即程式碼(Infrastructure as Code)
在官方可以了解到 puppet 是一個概念為`Infrastructure as Code`的工具。Infrastructure as Code 與一般撰寫的 shell scrip 類似，但是比後者更高一個層次，將這一層虛擬化，使管理者只需要定義 Infrastructure 的狀況即可。這樣除了可以模組化、reuse外，也可以清楚透過 code 了解環境安裝了什麼與設定了什麼，因此 code 就是一個 infrastructure。

### 資源(Resource)
Puppet 中一個基礎元素為`resource`，一個 resource 可以是`file`、`package`或者是`service`等，透過 resource 我們可以查看環境上檔案、套件、服務狀態等。更多資訊可以參考 [Resource 列表與使用方式](http://docs.puppetlabs.com/references/latest/type.html)。
> P.S resource type 要注意大小寫，當作 metaparameters 的時候寫作 Type[title] Type 要大寫。

### 相依性(Dependencies)
在使用 Puppet 時，通常會撰寫 manifest 檔案來定義 resource。而這些 resource 在執行時會以同步的方式完成。
> P.S 因為是同步(Sync)執行，故會有相依性的問題產生。這時候就可以用 Puppet 提供的 `before` / `require` 關鍵字來配置先後順序。


## Puppet 安裝與基本操作
### 環境建置
我們將使用兩台 Ubuntu 14.04  主機來進行操作，一台為`主控節點`，另一台為`Agent 節點`。下面是我們將用到的伺服器的基礎資訊：
* **puupet 主控節點**
    * IP：10.21.20.10
    * 主機名稱：puppetmaster
    * 完整主機名稱：puppetmaster.example.com
* **puupet agent 節點**
    * IP：10.21.20.8
    * 主機名稱：puppetslave
    * 完整主機名稱：puppetslave.example.com

在每台節點完成以下步驟：
```sh
$ sudo apt-get update && sudo apt-get -y install ntp
$ sudo vim /etc/ntp.conf

server 1.tw.pool.ntp.org iburst
server 3.asia.pool.ntp.org iburst
server 2.asia.pool.ntp.org iburst
```

### Puppet 主控節點部署
首先我們要先安裝 puppet 套件，透過`wget`下載`puppetlabs-release.deb`資源庫套件：
```sh
 $ wget https://apt.puppetlabs.com/puppetlabs-release-trusty.deb
 $ sudo dpkg -i puppetlabs-release-trusty.deb
 $ sudo apt-get update
```

完成後，我們就可以下載`puppetmaster-passenger`：
```sh
$ sudo apt-get install puppetmaster-passenger
```

安裝過程中會發現錯誤，這部分可以忽略：
```
Warning: Setting templatedir is deprecated. See http://links.puppetlabs.com/env-settings-deprecations
   (at /usr/lib/ruby/vendor_ruby/puppet/settings.rb:1139:in `issue_deprecation_warning')
```

安裝完後，可以透過以下指令查看版本：
```sh
$ puppet --version
3.8.4
```

這時我們可以透過`resource`指令來查看可用資源：
```sh
$ puppet resource [type]
$ puppet resource service

service { 'acpid':
  ensure => 'running',
  enable => 'true',
}
service { 'apache2':
  ensure => 'running',
}
```
> 更多的 resource 可以查看 [Type Reference](http://docs.puppetlabs.com/references/latest/type.html)。

在開始之前，我們先將 `apache2` 關閉，來讓 puppet 主控伺服器關閉：
```sh
$ sudo service apache2 stop
```

接著我們要建立一個檔案`/etc/apt/preferences.d/00-puppet.pref`來鎖定 APT 自動更新套件，因為套件更新會造成組態檔的混亂：
```sh
$ sudo vim /etc/apt/preferences.d/00-puppet.pref

Package: puppet puppet-common puppetmaster-passenger
Pin: version 3.8*
Pin-Priority: 501
```

Puppet 主控伺服器是一個認證推送機構，需要產生自己的認證，用於簽署所有 agent 的認證要求。首先要刪除所有該套件安裝過程建立的 ssl 憑證。預設憑證放在 `/var/lib/puppet/ssl`底下。
```sh
$ sudo rm  -rf /var/lib/puppet/ssl
```

接著我們要修改`puppet.conf` 檔案，來配置節點之前認證溝通，這邊要註解`templatedir`這行。然後在檔案的`[main]`增加以下資訊。
```sh
$ sudo vim /etc/puppet/puppet.conf

[main]
...
server = puppetmaster
environment = production
runinterval =  1h
strict_variables =  true
certname = puppetmaster
dns_alt_names = puppetmaster, puppetmaster.example.com
```
> 詳細的檔案可以參閱[Main Config File (puppet.conf)
](https://docs.puppetlabs.com/puppet/latest/reference/config_file_main.html)

修改完後，透過`puppet`指令建立新的憑證：
```sh
$ puppet master --verbose --no-daemonize

Info: Creating a new certificate revocation list
Info: Creating a new SSL key for puppetmaster
Info: csr_attributes file loading from /etc/puppet/csr_attributes.yaml
Info: Creating a new SSL certificate request for puppetmaster
Info: Certificate Request fingerprint (SHA256): 9B:C5:45:F8:C5:8F:C2:B1:4D:15:E3:64:5F:DB:19:AB:06:C4:60:99:48:F3:BA:8F:D3:03:7E:35:BE:BC:4E:B1
Notice: puppetmaster has a waiting certificate request
Notice: Signed certificate request for puppetmaster
Notice: Removing file Puppet::SSL::CertificateRequest puppetmaster at '/var/lib/puppet/ssl/ca/requests/puppetmaster.pem'
Notice: Removing file Puppet::SSL::CertificateRequest puppetmaster at '/var/lib/puppet/ssl/certificate_requests/puppetmaster.pem'
Notice: Starting Puppet master version 3.8.4
```
> 當看到`Notice: Starting Puppet master version 3.8.4`代表完成，這時候可用 `CTRL-C`離開。

檢查新產生的 SSL 憑證，可以使用以下指令：
```sh
$ puppet cert list -all

+ "puppetmaster" (SHA256) 8C:5E:39:A7:81:94:2B:09:7E:20:B8:F2:46:59:60:D9:FA:5D:4A:9E:BF:27:D7:C1:1A:A4:3E:97:12:D3:BE:21 (alt names: "DNS:puppet-master", "DNS:puppet-master.example.com", "DNS:puppetmaster")
```

### 設定一個 Puppet manifests
預設的 manifests 為`/etc/puppet/manifests/site.pp`。這個主要 manifests 檔案包括了用於在 Agent 節點執行的組態定義：
```sh
$ sudo vim /etc/puppet/manifests/site.pp

# execute 'apt-get update'
exec { 'apt-update': # exec resource named 'apt-update'
command => '/usr/bin/apt-get update' # command this resource will run
}

# install apache2 package
package { 'apache2':
require => Exec['apt-update'], # require 'apt-update' before installing
ensure => installed,
}

# ensure apache2 service is running
service { 'apache2':
ensure => running,
}
```
> 上面幾行用來部署 apache2 到 agent 節點。

完成後，修改`/etc/apache2/sites-enabled/puppetmaster.conf`檔，修改`SSLCertificateFile`與`SSLCertificateKeyFile`對應到新的憑證：
```sh
SSLCertificateFile      /var/lib/puppet/ssl/certs/puppetmaster.pem
SSLCertificateKeyFile   /var/lib/puppet/ssl/private_keys/puppetmaster.pem
```

然後重新開啟服務：
```sh
$ sudo service apache2 restart
```

### Puppet agent 節點部署
首先在 agent 節點上使用以下指令下載 puppet labs 的套件，並安裝：
```sh
$ wget https://apt.puppetlabs.com/puppetlabs-release-trusty.deb
$ sudo dpkg -i puppetlabs-release-trusty.deb
$ sudo apt-get update
$ sudo apt-get install -y puppet
```
由於 puppet 預設是不會啟動的，所以要編輯`/etc/default/puppet`檔案來設定：
```sh
$ sudo vim /etc/default/puppet

START=yes
```

之後一樣設定防止 APT 更新到 puppet，修改`/etc/apt/preferences.d/00-puppet.pref`檔案：
```sh
$ sudo vim /etc/apt/preferences.d/00-puppet.pref

Package: puppet puppet-common
Pin: version 3.8*
Pin-Priority: 501
```

### 設定 puppet agent
編輯`/etc/puppet/puppet.conf`檔案，將`templatedir`這行註解掉，並移除`[master]`部分的相關設定：
```sh
$ sudo vim /etc/puppet/puppet.conf

[main]
logdir=/var/log/puppet
vardir=/var/lib/puppet
ssldir=/var/lib/puppet/ssl
rundir=/var/run/puppet
factpath=$vardir/lib/facter
# templatedir=$confdir/templates

[agent]
server = puppetmaster.example.com
certname = puppetslave.example.com
```

完成後啟動 puppet：
```sh
$ sudo service puppet start
```

### 在主控伺服器上對憑證要求進行簽證
當完成 master 節點與 slave 節點後，可以在主控伺服器上使用以下指令來列出當前憑證請求：
```sh
$ puppet cert list

"puppetnode.example.com" (SHA256) 52:43:4C:ED:16:34:A3:EA:E7:5D:B0:97:FF:66:4F:C8:E0:51:AD:80:E6:32:95:53:FC:24:AE:15:17:17:3A:C0
```

接著使用以下指令進行簽證：
```sh
$ puppet cert sign puppetnode.example.com

Notice: Signed certificate request for puppetnode.example.com
Notice: Removing file Puppet::SSL::CertificateRequest puppetnode.example.com at '/var/lib/puppet/ssl/ca/requests/puppetnode.example.com.pem'
```
> 也可以使用`puppet cert sign --all`來一次簽署多個。

> 若想要移除可以使用`puppet cert clean hostname`。

簽署成功後，可以用以下指令查看：
```sh
$ puppet cert list --all

+ "puppetmaster"           (SHA256) 8C:5E:39:A7:81:94:2B:09:7E:20:B8:F2:46:59:60:D9:FA:5D:4A:9E:BF:27:D7:C1:1A:A4:3E:97:12:D3:BE:21 (alt names: "DNS:puppet-master", "DNS:puppet-master.example.com", "DNS:puppetmaster")
+ "puppetnode.example.com" (SHA256) EF:D6:E5:7E:45:B0:5D:EC:D4:17:E6:31:A2:97:F6:C2:31:2A:19:B9:0E:9D:31:77:9A:02:93:BC:73:B9:5E:58
```

### 部署主節點的 manifests
當配置並完成 puppet manifests，現在需要部署 manifests 到 slave 節點上。要載入 puppet manifests 可以使用以下指令：
```sh
$ puppet agent --test

Info: Retrieving pluginfacts
Info: Retrieving plugin
Info: Caching catalog for puppetnode.example.com
Info: Applying configuration version '1452086629'
Notice: /Stage[main]/Main/Exec[apt-update]/returns: executed successfully
Notice: Finished catalog run in 17.31 seconds
```

之後我們可以使用`puppet apply`來提交 manifests：
```sh
$ puppet apply /etc/puppet/manifests/site.pp
```

若要指定節點，可以建立如以下的`*.pp`檔：
```sh
$ sudo vim /etc/puppet/manifests/site-example.pp

node 'puppetslave1', 'puppetslave2' {
# execute 'apt-get update'
exec { 'apt-update': # exec resource named 'apt-update'
command => '/usr/bin/apt-get update' # command this resource will run
}

# install apache2 package
package { 'apache2':
require => Exec['apt-update'], # require 'apt-update' before installing
ensure => installed,
}

# ensure apache2 service is running
service { 'apache2':
ensure => running,
}
}
```

Puppet 是一個很成熟的工具，已有許多模組被貢獻，我們可以透過以下方式下載模組：
```sh
$  puppet module install puppetlabs-apache
```
> 注意，不要在一個已經部署 Apache 的環境上使用該模組，否則會清空為沒有被 puppet 管理的 apache 配置。

接著我們修改`site.pp`來配置 apache：
```sh
$ sudo vim /etc/puppet/manifest/site.pp

node 'puppetslave' {
class { 'apache': } # use apache module
apache::vhost { 'example.com': # define vhost resource
port => '8080',
docroot => '/var/www/html'
}
}
```

## 參考資源
* [Modules Search](https://forge.puppetlabs.com/)
* [InfoQ Puppet 介紹](http://www.infoq.com/cn/articles/introduction-puppet)
* [Puppet 學習](http://amyhehe.blog.51cto.com/9406021/1708500)
* [Puppet 筆記](http://blog.hsatac.net/2013/02/puppet-study-note/)
* [puppet學習筆記：puppet資源file詳細介紹](http://blog.csdn.net/linux_player_c/article/details/50148415)
* [How To Install Puppet To Manage Your Server Infrastructure](https://www.digitalocean.com/community/tutorials/how-to-install-puppet-to-manage-your-server-infrastructure)
