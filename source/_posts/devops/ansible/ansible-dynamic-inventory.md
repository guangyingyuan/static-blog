---
title: Ansible Dynamic Inventory
catalog: true
comments: true
date: 2016-02-17 14:23:01
categories:
- DevOps
tags:
- DevOps
- Automation Engine
- Ansible
---
在預設情況下，我們所使用的都是一個靜態的 Inventory 檔案，編輯主機、群組以及變數時都需要固定手動編輯完成。

Ansible 提供了 Dynamic Inventory 檔案，這個檔案是透過呼叫外部腳本或程式來產生指定的格式的 JSON 字串。這樣做的好處就是可以透過這個外部腳本與程式來管理系統（如 API）抓取最新資源訊息。

<!--more-->

 Ansible 使用者通常會互動於大多數的物理硬體，因此會有許多人可能也是`Cobbler`的使用者。
 > Cobbler 是一個透過網路部署 Linux 的服務，而且經過調整更能夠進行 Windows 部署。該工具是使用 Python 開發，因此輕巧便利，使用簡單指令就可以完成 PXE 網路安裝環境。

 比如說以下這個範例就是透過腳本程式產生的：
 ```sh
 {
    "production": ["delaware.example.com", "georgia.example.com",
        "maryland.example.com", "newhampshire.example.com",
        "newjersey.example.com", "newyork.example.com",
        "northcarolina.example.com", "pennsylvania.example.com",
        "rhodeisland.example.com", "virginia.example.com"
    ],
    "staging": ["ontario.example.com", "quebec.example.com"],
    "vagrant": ["vagrant1", "vagrant2", "vagrant3"],
    "lb": ["delaware.example.com"],
    "web": ["georgia.example.com", "newhampshire.example.com",
        "newjersey.example.com", "ontario.example.com", "vagrant1"
    ]
    "task": ["newyork.example.com", "northcarolina.example.com",
        "ontario.example.com", "vagrant2"
    ],
    "redis": ["pennsylvania.example.com", "quebec.example.com", "vagrant3"],
    "db": ["rhodeisland.example.com", "virginia.example.com", "vagrant3"]
}
 ```
使用方式如下：
1. **加上執行(x)的權限給 script**
2. **將 script 與 inventory file 放在同一目錄**

如此一來 ansible 就會自動讀取 inventory file 取得靜態的 inventory 資訊，並執行 script 取得動態的 inventory 資訊，將兩者 merge 後並使用。

目前官方已有提供幾個 Dynamic Inventory 的範例教學，如以下：
* [Cobbler External Inventory Script](http://docs.ansible.com/ansible/intro_dynamic_inventory.html#example-the-cobbler-external-inventory-script)
* [AWS EC2 External Inventory Script](http://docs.ansible.com/ansible/intro_dynamic_inventory.html#example-aws-ec2-external-inventory-script)
* [OpenStack External Inventory Script](http://docs.ansible.com/ansible/intro_dynamic_inventory.html#example-openstack-external-inventory-script)
