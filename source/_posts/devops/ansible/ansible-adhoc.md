---
title: Ansible Ad-Hoc 指令與 Modules
layout: default
comments: true
date: 2016-02-17 12:23:01
categories:
- DevOps
tags:
- DevOps
- Automation Engine
- Ansible
---
ad-hoc command（特設指令）簡單說就是直接執行指令，這些指令不需要要被保存在日後使用。在進行 Ansible 的 Playbook 語言之前，了解 ad-hoc 指令也可以幫助我們做一些快速的事情，不一定要寫出一個完整的 Playbooks 指令。

模組（也被稱為`Task plugins`或是`Library plugins`）是 Ansible 中實際執行的功能，它們會在每個 Playbook 任務中被執行，也可以透過 ansible 直接呼叫使用。目前 Ansible 已經擁有許多模組，可參閱 [Module Index](http://docs.ansible.com/ansible/modules_by_category.html)。

<!--more-->

首先我們先編輯`/etc/ansible/hosts`，加入以下內容：
```sh
[cluster]
ansible-slave-1 ansible_host=172.16.1.206
ansible-slave-2 ansible_host=172.16.1.207
ansible-slave-3 ansible_host=172.16.1.208
```

### Parallelism and Shell Commands
接下來我們將透過範例來說明 Ansible 的平行性與 Shell 指令，一開始我們需要將 ssh-agent 加入私有金鑰管理：
```sh
$ ssh-agent bash
$ ssh-add ~/.ssh/id_rsa
```
> 如果不想要透過 ssh-agent 的金鑰登入，可以在 ansible 指令使用`--ask-pass（-k）`參數，但是建議使用 ssh-agent。

剛剛我們在 Inventroy 檔案建立了一個群組（Cluster），裡面擁有三台主機，接下來我們透過執行一個簡單的指令與參數來實現並行執行：
```sh
$ ansible cluster -a "sleep 2" -f 1
```
> 上面的指令會隨機執行一台主機，完成後接下執行下一台，然而`-f`參數可以改變一次執行的 bash，好比改成：
```sh
$ ansible cluster -a "sleep 2" -f 3
```
會發現 bash 是平行執行的。

我們除了使用預設的 user 登入以外，也可以指定要登入的使用者：
```sh
$ ansible cluster -a "echo $USER" -u ubuntu
```

如果想透過特權（sudo）執行指令，可以透過以下方式：
```sh
$ ansible cluster -a "apt-get update" -u ubuntu --become
```
> 若該使用者沒有設定 sudo 不需要密碼的話，可以加入`--ask-sudo-pass（-k）`來驗證密碼。也可以使用`--become-method`來改變權限使用方法（預設為 sudo）。

也可以透過`--become-user`來切換使用者：
```sh
$ ansible cluster -a "echo $USER" -u ubuntu --become-user root
```
> 若有密碼，可以使用```--ask-sudo-pass```。


以上是基本的幾個指令，但當使用 ansible ad-hoc 指令時，會發現無法使用`shell 變數`以及`pipeline 等相關`，這是因為預設的 ansible ad-hoc 指令不支援，
故要改用 shell 模組來執行：
```sh
$ ansible cluster -m shell -a 'echo $(hostname) | grep -o "[0-9]"'
```
> 以上指令的`-m`表示要使用的模組。但要注意！使用 ansible 指令時要留意`"cmd"`與`'comd'`的差別，比如使用`"cmd"`會是抓取當前系統的資訊。

### File Transfer
Ansible 能夠以平行的方式同時`scp`大量的檔案到多台主機上，如以下範例：
```sh
$ ansible cluster -m copy -a "src=/etc/hosts dest=~/hosts"
```

也可以使用`file`模組做到修改檔案的權限與屬性（這邊可以將`copy`替換成`file`）：
```sh
$ ansible cluster -m file -a "dest=~/hosts mode=600"
$ ansible cluster -m file -a "dest=~/hosts mode=600 owner=ubuntu group=ubuntu"
```

`file`模組也能夠建立目錄：
```sh
$ ansible cluster -m file -a "dest=~/data mode=755 owner=ubuntu group=ubuntu state=directory"
```

若要刪除可以使用以下方式：
```sh
$ ansible cluster -m file -a "dest=~/data state=absent"
```

### Managing Packages
目前 Ansible 已經支援了`yum`與`apt`的模組，以下是一個`apt` 確認指定軟體名稱是否已安裝，並且不升級：
```sh
$ ansible cluster -m apt -a "name=ntp state=present"
```
> 也可以在`name=ntp`後面加版本號，如`name=ntp-{version}`。

若要確認是否為最新版本，可以使用以下指令：
```sh
$ ansible cluster -m apt -a "name=ntp state=latest"
```

若要確認一個軟體套件沒有安裝，可以使用以下指令：
```sh
$ ansible cluster -m apt -a "name=ntp state=absent" --become
```

更多的指令資訊可以查看 [About Modules](http://docs.ansible.com/ansible/modules.html)。

### Users and Groups
若想要建立系統使用者與群組，可以使用`user`模組，如以下範例：
```sh
$ ansible all -m user -a "name=food password=food" --become
```

刪除則如以下：
```sh
$ ansible all -m user -a "name=food state=absent" -b
```
> `--become`與`-b`是等效的。

### Deploying From Source Control
Ansible 不只可以透過`apt`與`ad-hoc 指令`來安裝與部署應用程式，也能用`git`模組來安裝：
```sh
$ ansible cluster -m git -a "repo=https://github.com/imac-cloud/Spark-tutorial.git dest=~/spark-tutorial" -f 3
```

### Managing Services
Ansible 也可以透過`service`模組來確認指定主機是否已啟動服務：
```sh
$ ansible cluster -m service -a "name=ssh state=started"
```
> 也可以改變`state`來執行對應動作，如`state=restarted`就會重新啟動服務。

### Time Limited Background Operations
有些操作需要長時間執行於後台，在指令開始執行後，可以持續檢查執行狀態，但是若不想要獲取該資訊可以使用以下指令：
```sh
$ ansible ansible-slave-1 -B 3600 -P 0 -a "/usr/bin/long_running_operation --do-stuff"
```

若要檢查執行狀態的話，可以使用`async_status`來傳入一個`jid`查看：
```sh
$ ansible cluster -m async_status -a "jid=488359678239.2844"
```

獲取狀態指令如下：
```sh
$ ansible ansible-slave-1 -B 1800 -P 60 -a "/usr/bin/long_running_operation --do-stuff"
```
> `-B`表示最常執行時間，`-P`表示每隔60秒回傳狀態。

### Gathering Facts
在 Playboooks 中有對 Facts 做一些描述，他表示的是一些系統`已知的變數`，若要查看所有 Facts，可以使用以下指令：
```sh
$ ansible cluster[0] -m setup
```

接下來可以針對 [Playbooks](http://docs.ansible.com/ansible/playbooks.html) 與 [Variables](http://docs.ansible.com/ansible/playbooks_variables.html) 進行研究。
