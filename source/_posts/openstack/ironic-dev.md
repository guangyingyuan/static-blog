---
title: 利用 OpenStack Ironic 提供裸機部署服務
layout: default
date: 2017-8-16 16:23:01
categories:
- OpenStack
tags:
- OpenStack
- DevStack
- Bare-metal
---
[Ironic](https://docs.openstack.org/ironic/latest/user/index.html) 是 OpenStack 專案之一，主要目的是提供裸機機器部署服務(Bare-metal service)。它能夠單獨或整合 OpenStack 其他服務被使用，而可整合服務包含 Keystone、Nova、Neutron、Glance 與 Swift 等核心服務。當使用 Compute 與 Network 服務對 Bare-metal 進行適當的配置時，OpenStack 可以透過 Compute API 同時部署虛擬機(Virtual machines)與裸機(Bare machines)。

本篇為了精簡安裝過程，故這邊不採用手動安裝教學(會在 Gitbook 書上更新)，因此採用 [DevStack](https://docs.openstack.org/devstack/latest/) 來部署服務，再手動設定一些步驟。

本環境安裝資訊：
* OpenStack Pike
* DevStack Pike
* Pike Pike Pike ....

<!--more-->

![](/images/openstack/openstack-ironic.png)
> P.S. 這邊因為我的 Manage net 已經有 MAAS 的服務，所以才用其他張網卡進行部署。

## 節點資訊
本次安裝作業系統採用`Ubuntu 16.04 Server`，測試環境為實體主機：

|   Role     |   CPU    |   Memory   |
|------------|----------|------------|
| controller |    4     |     16G    |
| bare-node1 |    4     |     16G    |

> 這邊 controller 為主要控制節點，將安裝大部分 OpenStack 服務。而 bare-node 為被用來做裸機部署的機器。

網卡若是實體主機，請設定為固定 IP，如以下：
```
auto eth0
iface eth0 inet static
       	address 172.20.3.93/24
       	gateway	172.20.3.1
       	dns-nameservers 8.8.8.8
```
> 若想修改主機的網卡名稱，可以編輯`/etc/udev/rules.d/70-persistent-net.rules`。

其中`controller`的`eth2`需設定為以下：
```
auto <ethx>
iface <ethx> inet manual
        up ip link set dev $IFACE up
        down ip link set dev $IFACE down
```

## 事前準備
安裝前需要確認叢集滿足以下幾點：
* 確認所有節點網路可以溝通。
* Bare-node IPMI 設定完成。包含 Address、User 與 Password。
* 修改 Controller 的 `/etc/apt/sources.list`，使用`tw.archive.ubuntu.com`。

## 安裝 OpenStack 服務
這邊採用 DevStack 來部署測試環境，首先透過以下指令取得 DevStack：
```sh
$ sudo useradd -s /bin/bash -d /opt/stack -m stack
$ echo "stack ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/stack
$ sudo su - stack
$ git clone https://git.openstack.org/openstack-dev/devstack
$ cd devstack
```

接著撰寫 local.conf 來描述部署過程所需的服務：
```sh
$ wget https://kairen.github.io/files/devstack/ironic.conf -O local.conf
$ sed -i 's/HOST_IP=.*/HOST_IP=172.22.132.93/g' local.conf
```
> `HOST_IP`請更換為自己環境 IP。有其他 Driver 請記得加入。

完成後執行部署腳本進行建置：
```sh
$ ./stack.sh
```
> 大約經過 15 min 就可以完成整個環境安裝。

測試 OpenStack 環境：
```sh
$ source openrc admin
$ openstack user list
+----------------------------------+----------------+
| ID                               | Name           |
+----------------------------------+----------------+
| 3ba4e813270e4e98ad781f4103284e0d | demo           |
| 40c6014bc18f407fbfbc22aadedb1ca0 | placement      |
| 567156ad1c7b4ccdbcd4ea02e7c44ce3 | alt_demo       |
| 7a22ce5036614993a707dd976c505ccd | swift          |
| 8d392f051afe45008289abca4dadf3ca | swiftusertest1 |
| a6e616af3bf04611bc23625e71a22e64 | swiftusertest4 |
| a835f1674648427396a7c6ac7e5eef06 | neutron        |
| b2bf73ef2eaa425c93e4f552e9266056 | swiftusertest2 |
| b7de1af8522b495c8a9fb743eb6e7f59 | nova           |
| cada5913a03e4f2794066902144264d3 | admin          |
| f03e39680b234474b139d00c3fbca989 | swiftusertest3 |
| f0a4033463f64c00858ff05525545b6d | glance-swift   |
| f2a1b186e7e84b10ae7e8f810e5c2412 | glance         |
| ff31787d136f4fba96c19af419b8559c | ironic         |
+----------------------------------+----------------+
```

測試 ironic 是否正常運行：
```sh
$ ironic node-list
+---------------------+----------------+
| Supported driver(s) | Active host(s) |
+---------------------+----------------+
| agent_ipmitool      | ironic-dev     |
| fake                | ironic-dev     |
| ipmi                | ironic-dev     |
| pxe_ipmitool        | ironic-dev     |
+---------------------+----------------+
```

### 建立 Bare metal 網路
首先我們需要設定一個網路來提供 DHCP, PXE 與其他需求使用，這部分會說明如何建立一個 Flat network 來提供裸機配置用。詳細可參考 [Configure the Networking service for bare metal provisioning](https://docs.openstack.org/ironic/latest/install/configure-networking.html)。

首先編輯`/etc/neutron/plugins/ml2/ml2_conf.ini`修改以下內容：
```
[ml2_type_flat]
flat_networks = public, physnet1

[ovs]
datapath_type = system
bridge_mappings = public:br-ex, physnet1:br-eth2
tunnel_bridge = br-tun
local_ip = 172.22.132.93
```

接著建立 bridge 來處理實體網路與 OpenStack 之間的溝通：
```sh
$ sudo ovs-vsctl add-br br-eth2
$ sudo ovs-vsctl add-port br-eth2 eth2
```

完成後重新啟動 Neutron server 與 agent：
```sh
$ sudo systemctl restart devstack@q-svc.service
$ sudo systemctl restart devstack@q-agt.service
```

建立完成後，OVS bridges 會類似如下：
```sh
$ sudo ovs-vsctl show

    Bridge br-int
        fail_mode: secure
        Port "int-br-eth2"
            Interface "int-br-eth2"
                type: patch
                options: {peer="phy-br-eth2"}
        Port br-int
            Interface br-int
                type: internal
    Bridge "br-eth2"
        Port "phy-br-eth2"
            Interface "phy-br-eth2"
                type: patch
                options: {peer="int-br-eth2"}
        Port "eth2"
            Interface "eth2"
        Port "br-eth2"
            Interface "br-eth2"
                type: internal
```

接著建立 Neutron flat 網路來提供使用：
```sh
$ neutron net-create sharednet1 \
                     --shared \
                     --provider:network_type flat \
                     --provider:physical_network physnet1

$ neutron subnet-create sharednet1 172.22.132.0/24 \
                        --name sharedsubnet1 \
                        --ip-version=4 --gateway=172.22.132.254 \
                        --allocation-pool start=172.22.132.180,end=172.22.132.200 \
                        --enable-dhcp
```
> P.S. neutron-client 在未來會被移除，故請轉用 [Provider network](https://docs.openstack.org/install-guide/launch-instance-networks-provider.html)。

### 設定 Ironic cleaning network
當使用到 [Node cleaning](http://docs.openstack.org/ironic/latest/admin/cleaning.html#node-cleaning) 時，我們必須設定`cleaning_network`選項來提供使用。首先取得 Network 資訊，透過以下指令：
```sh
$ openstack network list
+--------------------------------------+------------+----------------------------------------------------------------------------+
| ID                                   | Name       | Subnets                                                                    |
+--------------------------------------+------------+----------------------------------------------------------------------------+
| 03de10a0-d4d2-43ce-83db-806a5277dd29 | private    | 2a651bfb-776d-47f4-a958-f8a418f7fcd5, 99bdbd78-7a20-41b7-afa3-7cf7bf25b95b |
| 349a6a5b-1e26-4e36-8444-f6a6bbbdd227 | public     | 032a516e-3d55-4623-995d-06ee033eaee4, daf733a9-492e-4ea6-8a45-6364b88a8f6f |
| ade096bd-6a86-4d90-9cf4-bce9921f7257 | sharednet1 | 3f9f2a47-fdd9-472b-a6a2-ce6570e490ff                                       |
+--------------------------------------+------------+----------------------------------------------------------------------------+
```

編輯`/etc/ironic/ironic.conf`修改一下內容：
```
[neutron]
cleaning_network = sharednet1
```

完成後，重新啟動 Ironic 服務：
```sh
$ sudo systemctl restart devstack@ir-api.service
$ sudo systemctl restart devstack@ir-cond.service
```

### 建立 Deploy 與 User 映像檔
裸機服務在配置時需要兩組映像檔，分別為 `Deploy` 與 `User` 映像檔，其功能如下：
* `Deploy images`: 用來準備裸機服務機器以進行實際的作業系統部署，在 Cleaning 等階段會使用到。
* `User images`:最後安裝至裸機服務提供給使用者使用的作業系統映像檔。

由於 DevStack 預設會建立一組 Deploy 映像檔，這邊只針對 User 映像檔做手動建構說明，若要建構 Deploy 映像檔可以參考 [Building or downloading a deploy ramdisk image](https://docs.openstack.org/ironic/latest/install/deploy-ramdisk.html#deploy-ramdisk)。

首先我們必須先安裝`disk-image-builder`工具來提供建構映像檔：
```sh
$ virtualenv dib
$ source dib/bin/activate
(dib) $ pip install diskimage-builder
```

接著執行以下指令來進行建構映像檔：
```sh
$ cat <<EOF > k8s.repo
[kubernetes]
name=Kubernetes
baseurl=http://yum.kubernetes.io/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=0
repo_gpgcheck=0
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
       https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF

$ DIB_YUM_REPO_CONF=k8s.repo \
  DIB_DEV_USER_USERNAME=kyle \
  DIB_DEV_USER_PWDLESS_SUDO=yes \
  DIB_DEV_USER_PASSWORD=r00tme \
  disk-image-create \
        centos7 \
        dhcp-all-interfaces \
        devuser \
        yum \
        epel \
        baremetal \
        -o k8s.qcow2 \
        -p vim,docker,kubelet,kubeadm,kubectl,kubernetes-cni

...
Converting image using qemu-img convert
Image file k8s.qcow2 created...
```

完成後會看到以下檔案：
```sh
$ ls
dib  k8s.d  k8s.initrd  k8s.qcow2  k8s.repo  k8s.vmlinuz
```

上傳至 Glance 以提供使用：
```sh
# 上傳 Kernel
$ openstack image create k8s.kernel \
                      --public \
                      --disk-format aki \
                      --container-format aki < k8s.vmlinuz
# 上傳 Initrd
$ openstack image create k8s.initrd \
                      --public \
                      --disk-format ari \
                      --container-format ari < k8s.initrd
# 上傳 Qcow2
$ export MY_VMLINUZ_UUID=$(openstack image list | awk '/k8s.kernel/ { print $2 }')
$ export MY_INITRD_UUID=$(openstack image list | awk '/k8s.initrd/ { print $2 }')
$ openstack image create k8s \
                      --public \
                      --disk-format qcow2 \
                      --container-format bare \
                      --property kernel_id=$MY_VMLINUZ_UUID \
                      --property ramdisk_id=$MY_INITRD_UUID < k8s.qcow2
```

## 建立 Ironic 節點
在所有服務配置都完成後，這時候要註冊實體機器資訊，來提供給 Compute 服務部署時使用。首先確認 Ironic 的 Driver 是否有資源機器的 Power driver：
```sh
$ ironic driver-list
+---------------------+----------------+
| Supported driver(s) | Active host(s) |
+---------------------+----------------+
| agent_ipmitool      | ironic-dev     |
| fake                | ironic-dev     |
| ipmi                | ironic-dev     |
| pxe_ipmitool        | ironic-dev     |
+---------------------+----------------+
```
> 若有缺少的話，請參考 [Set up the drivers for the Bare Metal service](https://docs.openstack.org/ironic/latest/install/setup-drivers.html)。

確認有支援後，透過以下指令來建立 Node，並進行註冊：
```sh
$ export DEPLOY_VMLINUZ_UUID=$(openstack image list | awk '/ipmitool.kernel/ { print $2 }')
$ export DEPLOY_INITRD_UUID=$(openstack image list | awk '/ipmitool.initramfs/ { print $2 }')
$ ironic node-create -d agent_ipmitool \
                     -n bare-node-1 \
                     -i ipmi_address=172.20.3.194 \
                     -i ipmi_username=maas \
                     -i ipmi_password=passwd \
                     -i ipmi_port=623 \
                     -i deploy_kernel=$DEPLOY_VMLINUZ_UUID \
                     -i deploy_ramdisk=$DEPLOY_INITRD_UUID
```
> 若使用 Console 的話，要加入`-i ipmi_terminal_port=9000`，可參考 [Configuring Web or Serial Console](https://docs.openstack.org/ironic/latest/admin/console.html)。

接著更新機器資訊，由於這邊沒有使用 inspector，故要自己設定機器資訊：
```sh
$ export NODE_UUID=$(ironic node-list | awk '/bare-node-1/ { print $2 }')
$ ironic node-update $NODE_UUID add \
                     properties/cpus=4 \
                     properties/memory_mb=8192 \
                     properties/local_gb=100 \
                     properties/root_gb=100 \
                     properties/cpu_arch=x86_64
```

然後透過 port create 來把 Node 的所有網路資訊進行註冊：
```sh
$ ironic port-create -n $NODE_UUID -a NODE_MAC_ADDRESS
```
> 這邊`NODE_MAC_ADDRESS`是指`bare-node-1`節點的 PXE(eth1)網卡 Mac Address，如 54:a0:50:85:d5:fa。

完成後透過 validate 指令來檢查：
```sh
$ ironic node-validate $NODE_UUID
+------------+--------+-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| Interface  | Result | Reason                                                                                                                                                                                                |
+------------+--------+-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| boot       | False  | Cannot validate image information for node 0c20cf7d-0a36-46f4-ac38-721ff8bfb646 because one or more parameters are missing from its instance_info. Missing are: ['ramdisk', 'kernel', 'image_source'] |
| console    | True   |                                                                                                                                                                                                       |
| deploy     | False  | Cannot validate image information for node 0c20cf7d-0a36-46f4-ac38-721ff8bfb646 because one or more parameters are missing from its instance_info. Missing are: ['ramdisk', 'kernel', 'image_source'] |
| inspect    | None   | not supported                                                                                                                                                                                         |
| management | True   |                                                                                                                                                                                                       |
| network    | True   |                                                                                                                                                                                                       |
| power      | True   |                                                                                                                                                                                                       |
| raid       | True   |                                                                                                                                                                                                       |
| storage    | True   |                                                                                                                                                                                                       |
+------------+--------+-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
```
> P.S. 這邊`boot`與`deploy`的錯誤若是如上所示的話，可以直接忽略，這是因為使用 Nova 來管理 baremetal 會出現的問題。

最後利用 provision 指令來測試節點是否能夠提供服務：
```sh
$ ironic --ironic-api-version 1.34 node-set-provision-state $NODE_UUID manage
$ ironic --ironic-api-version 1.34 node-set-provision-state $NODE_UUID provide
$ ironic node-list
+--------------------------------------+--------+---------------+-------------+--------------------+-------------+
| UUID                                 | Name   | Instance UUID | Power State | Provisioning State | Maintenance |
+--------------------------------------+--------+---------------+-------------+--------------------+-------------+
| 0c20cf7d-0a36-46f4-ac38-721ff8bfb646 | bare-0 | None          | power off   | cleaning           | False       |
+--------------------------------------+--------+---------------+-------------+--------------------+-------------+
```
> 這時候機器會進行 clean 過程，經過一點時間就會完成，若順利完成則該節點就可以進行部署了。若要了解細節狀態，可以參考 [Ironic’s State Machine](https://docs.openstack.org/ironic/latest/contributor/states.html)。

![](/images/openstack/ironic-clean.png)

## 透過 Nova 部署 baremetal 機器
最後我們要透過 Nova API 來部署裸機，在開始前要建立一個 flavor 跟上傳 keypair 來提供使用：
```sh
$ ssh-keygen -t rsa
$ openstack keypair create --public-key ~/.ssh/id_rsa.pub default
$ openstack flavor create --vcpus 4 --ram 8192 --disk 100 baremetal.large
```

完成後，即可透過以下指令進行部署：
```sh
$ NET_ID=$(openstack network list | awk '/sharednet1/ { print $2 }')
$ openstack server create --flavor baremetal.large \
                          --nic net-id=$NET_ID \
                          --image k8s \
                          --key-name default k8s-01
```

經過一段時間後，就會看到部署完成，這時候可以透過以下指令來確認部署結果：
```sh
$ openstack server list
+--------------------------------------+--------+--------+---------------------------+-------+-----------------+
| ID                                   | Name   | Status | Networks                  | Image | Flavor          |
+--------------------------------------+--------+--------+---------------------------+-------+-----------------+
| a40e5cb1-dfc6-44d5-b638-648e8c0975fb | k8s-01 | ACTIVE | sharednet1=172.22.132.187 | k8s   | baremetal.large |
+--------------------------------------+--------+--------+---------------------------+-------+-----------------+

$ openstack baremetal list
+--------------------------------------+--------+--------------------------------------+-------------+--------------------+-------------+
| UUID                                 | Name   | Instance UUID                        | Power State | Provisioning State | Maintenance |
+--------------------------------------+--------+--------------------------------------+-------------+--------------------+-------------+
| 0c20cf7d-0a36-46f4-ac38-721ff8bfb646 | bare-0 | a40e5cb1-dfc6-44d5-b638-648e8c0975fb | power on    | active             | False       |
+--------------------------------------+--------+--------------------------------------+-------------+--------------------+-------------+
```

最後透過 ssh 來進入部署機器來建立應用：
```sh
$ ssh kyle@172.22.132.187
[kyle@host-172-22-132-187 ~]$ sudo systemctl start kubelet.service
[kyle@host-172-22-132-187 ~]$ sudo systemctl start docker.service
[kyle@host-172-22-132-187 ~]$ sudo kubeadm init --service-cidr 10.96.0.0/12 \
                                                --kubernetes-version v1.7.4 \
                                                --pod-network-cidr 10.244.0.0/16 \
                                                --apiserver-advertise-address 172.22.132.187 \
                                                --token b0f7b8.8d1767876297d85c
```
> 整合`Magnum`有空再寫，先簡單玩玩吧。

若是懶人可以用 Dashboard 來部署，另外本教學的 DevStack 有使用 Ironic UI，因此可以在以下頁面看到 node 資訊。
![](/images/openstack/ironic-ui.png)
