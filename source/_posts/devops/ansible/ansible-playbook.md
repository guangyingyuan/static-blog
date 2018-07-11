---
title: Ansible Playbooks
catalog: true
comments: true
date: 2016-02-18 12:23:01
categories:
- DevOps
tags:
- DevOps
- Automation Engine
- Ansible
---
Playbooks 是 Ansible 的設定、部署與編配語言等。可以被用來描述一個被遠端的主機要執行的指令方案，或是一組 IT 行程執行的指令集合。

在基礎層面上，Playbooks 可以被用來管理部署到遠端主機的組態檔案，在更高階層上 Playbooks 可以循序對多層式架構上的伺服器執行線上的 Polling 更新內部的操作，並將操作委派給其他主機，包含過程中發生的監視器服務、負載平衡伺服器等。

<!--more-->

Playbooks 被設計成易懂與基於 Text Language 的二次開發，有許多方式可以組合 Playbooks 與其附屬的檔案。建議在閱讀 Playbooks 時，同步閱讀 [Example Playbooks](https://github.com/ansible/ansible-examples)。

Playbooks 與 ad-hoc 相比是一種完全不同的 Ansible 應用方式，該方式也是 Ansible 強大之處。簡單來說 Playbooks 是一種組態管理系統與多機器部署系統基礎，與現有系統不同之處在於非常適合複雜的部署。若想參考範例，可以參閱 [ansible-examples repository](https://github.com/ansible/ansible-examples)。

### Playbook Language Example
Playbook 採用 [YAML 語法](http://ansible-tran.readthedocs.org/en/latest/docs/YAMLSyntax.html)來表示。playbook 由一或多個`plays`組成的內容為元素的列表。在`play`中一組機器會被映射成定義好的角色，在 Ansible 中`play`內容也被稱為`tasks`。

以下是一個簡單的範例：
```txt
---
- name: Configure cluster with apache
  hosts: cluster
  sudo: yes
  remote_user: ubuntu
  tasks:
    - name: install apache2
      apt: name=apache2 update_cache=yes state=latest

    - name: enabled mod_rewrite
      apache2_module: name=rewrite state=present
      notify:
        - restart apache2

    - name: apache2 listen on port 8081
      lineinfile: dest=/etc/apache2/ports.conf regexp="^Listen 80" line="Listen 8081" state=present
      notify:
        - restart apache2

    - name: apache2 virtualhost on port 8081
      lineinfile: dest=/etc/apache2/sites-available/000-default.conf regexp="^<VirtualHost \*:80>" line="<VirtualHost *:8081>" state=present
      notify:
        - restart apache2

  handlers:
    - name: restart apache2
      service: name=apache2 state=restarted
```

從以上範例中，可以由上往下大概知道結構如何，但我們還是要依序講解一下。
