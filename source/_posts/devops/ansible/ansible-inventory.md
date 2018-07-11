---
title: Ansible Inventory
catalog: true
comments: true
date: 2016-02-17 12:23:01
categories:
- DevOps
tags:
- DevOps
- Automation Engine
- Ansible
---
Ansible 在同一時間能夠工作於多個系統，透過在 inventory file 所列舉的主機與群組來執行對應的指令，該檔案預設存於`/etc/ansible/hosts`。

IT 人員不只能夠使用預設的檔案，也能夠在同一時間使用多個檔案，甚至來抓取來至雲端的 inventory 檔案，這是一個是動態的 inventory ，這部分可以參考 [Dynamic Inventory](http://docs.ansible.com/ansible/intro_dynamic_inventory.html)。

<!--more-->

### Hosts and Groups
Inventory 是一個`INI-like`格式的檔案，如以下範例所示：
```
mail.example.com

[webservers]
foo.example.com
bar.example.com

[dbservers]
one.example.com
two.example.com
three.example.com
```

如果 SSH 不是標準 Port 的話，可以使用`:`來對應要使用的 Port。但在 SSH config 檔案所列出來的主機將不會與 paramiko 進行連線，但是會與 OpenSSH 進行連接使用。
```
badwolf.example.com:5309
```
> 雖然可以使用以上方式達到不同 Port 連接，但是還是建議使用預設 Port。

假設只有靜態 IP，但又希望透過一些別名（aliases）來表示主機，或透過不同 Port 連接的話，可以表示如以下：
```
jumper ansible_port=5555 ansible_host=192.168.1.50
```

若要一次列出多個主機可以使用以下 Pattern：
```
[webservers]
www[01:50].example.com
```

在數字 Pattern，前導的 0 可以根據需求刪除或加入。不只可以定義數字型，還能定義英文字母範圍：
```
[databases]
db-[a:f].example.com
```

也可以為每台主機的設定基礎連線類型與使用者資訊：
```
[targets]
localhost           ansible_connection=local
other1.example.com  ansible_connection=ssh  ansible_user=mpdehaan
other2.example.com  ansible_connection=ssh  ansible_user=mdehaan
```

### Host Variables
如上述範例，我們可以很容易將變數分配給將在 Playbooks 使用的主機：
```
[atlanta]
host1   http_port=80    maxRequestsPerChild=808
host2   http_port=303   maxRequestsPerChild=909
```

### Group Variables
變數也能夠被應用到整個群組裡：
```
[atlanta]
host1
host2

[atlanta:vars]
ntp_server=ntp.atlanta.example.com
proxy=proxy.atlanta.example.com
```

### Groups of Groups, and Group Variables
另外，也可以用`:children` 來建立群組中的群組，並使用`:vars`來設定變數：
```
[atlanta]
host1
host2

[raleigh]
host2
host3

[southeast:children]
atlanta
raleigh

[southeast:vars]
some_server=foo.southeast.example.com
halon_system_timeout=30
self_destruct_countdown=60
escape_pods=2

[usa:children]
southeast
northeast
southwest
northwest
```

### Splitting Out Host and Group Specific Data
該部分說明想要儲存 list 與 hash table 資料，或者從 Inventory 檔案保持分離主機與群組的特定變數。在 Ansible 的第一優先作法實際上是不儲存變數於主 Inventort 檔案。

除了直接在 INI 檔案儲存變數外，主機與群組變數也可以儲存在個人相對的 Inventory 檔案。這些變數檔案格式為 YAML。有效的副檔名如`.yml`、`.yaml`，以及`.json`或`沒有副檔名`。

一般當 remote host 數量不多時，把變數定義在 inventory 中是 ok 的；但若 remote host 的數量越來越多時，將變數的宣告定義在外部的檔案中會是比較好的方式。

假設 Inventory 檔案路徑為：
```
/etc/ansible/hosts
```

如果主機被命名為`foosball`以及在`raleigh`與`webservers`的群組，以下位置的 YAML 檔案變數將提供給主機使用：
```sh
# can optionally end in '.yml', '.yaml', or '.json'
/etc/ansible/group_vars/raleigh
/etc/ansible/group_vars/webservers
/etc/ansible/host_vars/foosball
```
ansible 會自動尋找 playbook 所在的目錄中的`host_vars`目錄 以及`group_vars`目錄 中所包含的檔案，並使用定義在這兩個目錄中的變數資訊。

舉例來說，inventory / playbook / host_vars / group_vars 可以用類似以下的方式進行配置：
* **inventory**：/home/vagrant/ansible/playbooks/inventory
* **playbook**：/home/vagrant/ansible/playbooks/myplaybook
* **host_vars**：/home/vagrant/ansible/playbooks/host_vars/prod1.example.com.tw
* **group_vars**：/home/vagrant/ansible/playbooks/group_vars/production

變數定義的方式有兩種方式：
```sh
db_primary_host: prod1.example.com.tw
db_replica_host: prod2.example.com.tw
db_name: widget_production
db_user: widgetuser
db_password: lastpassword
redis_host: redis_stag.example.com.tw
```

也可以用 YAML 的方式定義：
```sh
---
db:
    user: widgetuser
    password: lastpassword
    name: widget_production
    primary:
        host: prod1.example.com.tw
        port: 5432
    replica:
        host: prod2.example.com.tw
        port: 5432
redis:
    host: redis_stag.example.com.tw
    port: 6379
```

甚至可以在繼續細分，定義檔案`../playbooks/group_vars/production/db`：
```sh
---
db:
    user: widgetuser
    password: lastpassword
    name: widget_production
    primary:
        host: prod1.example.com.tw
        port: 5432
    replica:
        host: prod2.example.com.tw
        port: 5432
```

### List of Behavioral Inventory Parameters
正如上述提到，設定以下變數可以定義 Ansible 該如何控制以及遠端主機。如主機連線：
```sh
ansible_connection
  Connection type to the host. Candidates are local, smart, ssh or paramiko.  The default is smart.
```

SSH connection：
```
ansible_host
  The name of the host to connect to, if different from the alias you wish to give to it.
ansible_port
  The ssh port number, if not 22
ansible_user
  The default ssh user name to use.
ansible_ssh_pass
  The ssh password to use (this is insecure, we strongly recommend using --ask-pass or SSH keys)
ansible_ssh_private_key_file
  Private key file used by ssh.  Useful if using multiple keys and you don't want to use SSH agent.
ansible_ssh_common_args
  This setting is always appended to the default command line for
  sftp, scp, and ssh. Useful to configure a ``ProxyCommand`` for a
  certain host (or group).
ansible_sftp_extra_args
  This setting is always appended to the default sftp command line.
ansible_scp_extra_args
  This setting is always appended to the default scp command line.
ansible_ssh_extra_args
  This setting is always appended to the default ssh command line.
ansible_ssh_pipelining
  Determines whether or not to use SSH pipelining. This can override the
  ``pipelining`` setting in ``ansible.cfg``.
```

權限提升（可參閱[Ansible Privilege Escalation](http://docs.ansible.com/ansible/become.html)）：
```
ansible_become
  Equivalent to ansible_sudo or ansible_su, allows to force privilege escalation
ansible_become_method
  Allows to set privilege escalation method
ansible_become_user
  Equivalent to ansible_sudo_user or ansible_su_user, allows to set the user you become through privilege escalation
ansible_become_pass
  Equivalent to ansible_sudo_pass or ansible_su_pass, allows you to set the privilege escalation password
```

遠端主機環境參數：
```
ansible_shell_type
  The shell type of the target system. Commands are formatted using 'sh'-style syntax by default. Setting this to 'csh' or 'fish' will cause commands executed on target systems to follow those shell's syntax instead.
ansible_python_interpreter
  The target host python path. This is useful for systems with more
  than one Python or not located at "/usr/bin/python" such as \*BSD, or where /usr/bin/python
  is not a 2.X series Python.  We do not use the "/usr/bin/env" mechanism as that requires the remote user's
  path to be set right and also assumes the "python" executable is named python, where the executable might
  be named something like "python26".
ansible\_\*\_interpreter
  Works for anything such as ruby or perl and works just like ansible_python_interpreter.
  This replaces shebang of modules which will run on that host.
```

一個主機檔案範例：
```
some_host         ansible_port=2222     ansible_user=manager
aws_host          ansible_ssh_private_key_file=/home/example/.ssh/aws.pem
freebsd_host      ansible_python_interpreter=/usr/local/bin/python
ruby_module_host  ansible_ruby_interpreter=/usr/bin/ruby.1.9.3
```
