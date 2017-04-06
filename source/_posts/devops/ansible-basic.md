---
title: Ansible 介紹與使用
layout: default
comments: true
date: 2016-02-16 12:23:01
categories:
- DevOps
tags:
- DevOps
- Automation Engine
---
Ansible 是最近越來越夯多 DevOps 自動化組態管理軟體，從 2013 年發起的專案，由於該架構為無 agent 程式的架構，以部署靈活與程式碼易讀而受到矚目。Ansible 除了有開源版本之外，還針對企業用戶推出 Ansible Tower 版本，已有許多知名企業採用，如 Apple、Twitter 等。

Ansible 架構圖如下所示，使用者透過 Ansible 編配操控公有與私有雲或 CMDB（組態管理資料庫）中的主機，其中 Ansible 編排是由`Inventory(主機與群組規則)`、`API`、`Modules(模組)`與`Plugins(插件)`組合而成。

<center>![](/images/devops/ansible-arch.jpg)</center>
<!--more-->

[Ansible](https://github.com/ansible/ansible) 與其他管理工具最大差異在於不需要任何 Agent，預設使用 SSH 來做遠端操控與配置，並採用 YAML 格式來描述配置資訊。
> Ansible 提供了一個 Playbook 分享平台，可以讓管理與開發者上傳自己的功能與角色配置的 Playbook，該網址為 [Ansible Galaxy](https://galaxy.ansible.com/intro)。

**優點：**
* 開發社群活躍。
* playbook 使用的 yaml 語言，很簡潔。
* 社群相關文件容易理解。。
* 沒有 Agent 端。
* 安裝與執行的速度快
* 配置簡單、功能強大、擴展性強
* 可透過 Python 擴展功能
* 提供用好的 Web 管理介面與 REST API 介面（AWX 平台）

**缺點：**
* Web UI 需要收費。
* 官方資料都比較淺顯。

## Ansible 安裝與基本操作
Ansible 有許多種安裝方式，如使用 Github 來透過 Source Code 安裝，也可以透過 python-pip 來安裝，甚至是使用作業系統的套件管理系統安裝，以下使用 Ubuntu APT 來進行安裝：
```sh
$ sudo apt-get install software-properties-common
$ sudo apt-add-repository ppa:ansible/ansible
$ sudo apt-get update
$ sudo apt-get install ansible
```

也可以使用 Python-pip 來進行安裝：
```sh
$ sudo easy_install pip
$ sudo pip install -U pip
$ sudo pip install ansible
```

### 節點準備
首先我們要在各節點先安裝 SSH Server ，並配置需要的相關環境：
```sh
$ sudo apt-get install openssh-server
```

設定特權模式不需要輸入密碼：
```sh
$ echo "ubuntu ALL = (root) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/ubuntu
$ sudo chmod 440 /etc/sudoers.d/ubuntu
```
> 這邊 User 為`ubuntu`，若使用者不一樣請更換。

建立 SSH Key，並複製 Key 使之不用密碼登入：
```sh
$ ssh-keygen -t rsa
$ ssh-copy-id localhost
```

新增各節點 Domain name 至`/etc/hosts`檔案：
```sh
172.16.1.205 ansible-master
172.16.1.206 ansible-slave-1
172.16.1.207 ansible-slave-2
172.16.1.208 ansible-slave-3
```

並在 Master 節點複製所有 Slave 的 SSH Key：
```sh
$ ssh-copy-id ubuntu@ansible-slave-1
$ ssh-copy-id ubuntu@ansible-slave-2
...
```

### 設定 Invetory File
Ansible 能夠在同一時間工作於多個基礎設施的系統中。透過作用於 Ansible 的 Inventory 檔案所列出的主機與群組，該檔案預設被存在`/etc/ansible/hosts`。

`/etc/ansible/hosts` 是一個 INI-like  的檔案格式，如以下內容：
```
ansible-slave-1
ansible-slave-2
ansible-slave-3
```
> 也可以建立成 Groups，如以下內容：
```sh
[openstack]
ansible-slave-1
ansible-slave-2
ansible-slave-3
```

> 若要參考更多資訊，可看 [Invetory File](http://docs.ansible.com/ansible/intro_inventory.html)。

### 基本功能操作
Ansible 基本操作如以下指令：
```sh
$ ansible <pattern_goes_here> -m <module_name> -a <arguments>
```
> `<pattern_goes_here>`部分可以參考 [Patterns](http://docs.ansible.com/ansible/intro_patterns.html)。

比如我們可以用 Ping 模組來測試是否連線成功：
```sh
$ ansible all -m ping

ansible-slave-2 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
ansible-slave-3 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
ansible-slave-1 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```
> 其中`all`為所有 Invetory 的主機，`-m`為使用的模組。若使用指定的 Inventory 檔案可以使用`-i`。


也可以執行指定指令：
```sh
$ ansible all -a "/bin/echo hello"
```
> `-a` 後面為要執行的指令。

若要指定登入的使用者，且執行特權模式，可以使用以下指令：
```sh
$ ansible all -a "apt-get update" -u vagrant -b
```
> `-u`為登入使用者，`-b` 為切換成特權模式（root），早期版本為`--sudo`。

### 主機的 SSH Key 檢查
在 Ansible 1.2.1 與之後的版本預設都需要做主機 SSH key 檢查。

如果一台主機重新安裝或者在 'known_hosts'  有不同的 SSH Key 的話，將會導致錯誤發生，但不希望這樣的問題影響 Ansible 使用，可以在 `/etc/ansible/ansible.cfg` 或者`~/.ansible.cfg`檔案關閉檢查。
```sh
[defaults]
host_key_checking = False
```

也可以代替為設定環境變數：
```sh
$ export ANSIBLE_HOST_KEY_CHECKING=False
```

還要注意在 paramiko 模式主機金鑰檢查緩慢是合理的
，因此建議切換使用 SSH。

Ansible 會在遠端系統上記錄有關模組參數的一些資訊存於 syslog，除非該執行任務有標示 'no_log: True'。
