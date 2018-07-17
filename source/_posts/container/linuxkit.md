---
title: 品嚐 Moby LinuxKit 的 Linux 作業系統
date: 2017-4-23 17:08:54
catalog: true
categories:
- Container
tags:
- Linux
- Docker
- Moby
- Microkernel
---
[LinuxKit](https://github.com/linuxkit/linuxkit) 是 [DockerCon 2017](http://www.nebulaworks.com/blog/2017/04/22/docker-captains-dockercon-2017-review/) 中推出的工具之一，其主要是以 Container 來建立最小、不可變的 Linux 作業系統映像檔框架，Docker 公司一直透過 LinuxKit 來建立相關產品，如 Docker for Mac 等。由於要最快的了解功能，因此這邊透過建立簡單的映像檔來學習。

![](/images/docker/linux-kit.png)

<!--more-->

在開始前需要準備完成一些事情：
* 安裝 Git client。
* 安裝 Docker engine，這邊建立使用 Docker-ce 17.04.0。
* 安裝 GUN make 工具。
* 安裝 GUN tar 工具。

## 建構 Moby 工具
首先我們要建構名為 Moby 的工具，這個工具主要提供指定的 YAML 檔來執行描述的建構流程與功能，並利用 Docker 來建構出 Linux 作業系統。在本教學中，最後我們會利用 [xhyve](https://github.com/mist64/xhyve) 這個 OS X 的虛擬化來提供執行系統實例，當然也可以透過官方的 [HyperKit](https://github.com/moby/hyperkit) 來進行。

首先透過 Git 來抓取 LinuxKit repos，並進入建構 Moby：
```sh
$ git clone https://github.com/linuxkit/linuxkit.git
$ cd linuxkit
$ make && sudo make install
$ moby version
moby version 0.0
commit: 34d508562d7821cb812dd7b9caf4d9fbcdbc9fef
```

### 建立 Linux 映像檔
當完成建構 Moby 工具後，就可以透過撰寫 YAML 檔來描述 Linux 的建構功能與流程了，這邊建立一個 Docker + SSH 的 Linux 映像檔。首先建立檔名為`docker-sshd.yml`的檔案，然後加入以下內容：
```yaml
kernel:
  image: "linuxkit/kernel:4.9.x"
  cmdline: "console=ttyS0 console=tty0 page_poison=1"
init:
  - linuxkit/init:63eed9ca7a09d2ce4c0c5e7238ac005fa44f564b
  - linuxkit/runc:b0fb122e10dbb7e4e45115177a61a3f8d68c19a9
  - linuxkit/containerd:18eaf72f3f4f9a9f29ca1951f66df701f873060b
  - linuxkit/ca-certificates:e091a05fbf7c5e16f18b23602febd45dd690ba2f
onboot:
  - name: sysctl
    image: "linuxkit/sysctl:1f5ec5d5e6f7a7a1b3d2ff9dd9e36fd6fb14756a"
    net: host
    pid: host
    ipc: host
    capabilities:
     - CAP_SYS_ADMIN
    readonly: true
  - name: sysfs
    image: linuxkit/sysfs:6c1d06f28ddd9681799d3950cddf044b930b221c
  - name: binfmt
    image: "linuxkit/binfmt:c7e69ebd918a237dd086a5c58dd888df772746bd"
    binds:
     - /proc/sys/fs/binfmt_misc:/binfmt_misc
    readonly: true
  - name: format
    image: "linuxkit/format:53748000acf515549d398e6ae68545c26c0f3a2e"
    binds:
     - /dev:/dev
    capabilities:
     - CAP_SYS_ADMIN
     - CAP_MKNOD
  - name: mount
    image: "linuxkit/mount:d2669e7c8ddda99fa0618a414d44261eba6e299a"
    binds:
     - /dev:/dev
     - /var:/var:rshared,rbind
    capabilities:
     - CAP_SYS_ADMIN
    rootfsPropagation: shared
    command: ["/mount.sh", "/var/lib/docker"]
services:
  - name: rngd
    image: "linuxkit/rngd:c42fd499690b2cb6e4e6cb99e41dfafca1cf5b14"
    capabilities:
     - CAP_SYS_ADMIN
    oomScoreAdj: -800
    readonly: true
  - name: dhcpcd
    image: "linuxkit/dhcpcd:57a8ef29d3a910645b2b24c124f9ce9ef53ce703"
    binds:
     - /var:/var
     - /tmp/etc:/etc
    capabilities:
     - CAP_NET_ADMIN
     - CAP_NET_BIND_SERVICE
     - CAP_NET_RAW
    net: host
    oomScoreAdj: -800
  - name: ntpd
    image: "linuxkit/openntpd:a570316d7fc49ca1daa29bd945499f4963d227af"
    capabilities:
      - CAP_SYS_TIME
      - CAP_SYS_NICE
      - CAP_SYS_CHROOT
      - CAP_SETUID
      - CAP_SETGID
    net: host
  - name: docker
    image: "linuxkit/docker-ce:741bf21513328f674e0cdcaa55492b0b75974e08"
    capabilities:
     - all
    net: host
    mounts:
     - type: cgroup
       options: ["rw","nosuid","noexec","nodev","relatime"]
    binds:
     - /var/lib/docker:/var/lib/docker
     - /lib/modules:/lib/modules
  - name: sshd
    image: "linuxkit/sshd:e108d208adf692c8a0954f602743e0eec445364e"
    capabilities:
    - all
    net: host
    pid: host
    binds:
      - /root/.ssh:/root/.ssh
      - /etc/resolv.conf:/etc/resolv.conf
  - name: test-docker-bench
    image: "linuxkit/test-docker-bench:2f941429d874c5dcf05e38005affb4f10192e1a8"
    ipc: host
    pid: host
    net: host
    binds:
    - /run:/var/run
    capabilities:
    - all
files:
  - path: etc/docker/daemon.json
    contents: '{"debug": true}'
  - path: root/.ssh/authorized_keys
    contents: 'SSH_KEY'
trust:
  image:
    - linuxkit/kernel
    - linuxkit/binfmt
    - linuxkit/rngd
outputs:
  - format: kernel+initrd
  - format: iso-bios
```
> `P.S.`請修改`SSH_KEY`內容為你的系統 ssh public key。

這邊說明幾個 YAML 格式意義：
* **kernel**: 指定 Docker 映像檔的核心版本，會包含一個 Linux 核心與檔案系統的 tar 檔，會將核心建構在`/kernel`目錄中。
* **init**: 是一個 Docker Container 的 init 行程基礎，裡面包含`init`、`containerd`、`runC`與其他等工具。
* **onboot**: 指定要建構的系統層級工具，會依據定義順序來執行，該類型如: dhcpd 與 ntpd 等。
* **services**: 指定要建構服務，通常會是系統開啟後執行，如 ngnix、apache2。
* **files**:要複製到該 Linux 系統映像檔中的檔案。
* **outputs**:輸出的映像檔格式。

> 更多 YAML 格式說明可以參考官方 [LinuxKit YAML](https://github.com/linuxkit/linuxkit/blob/master/docs/yaml.md)。目前 LinuxKit 的映像檔來源可以參考 [Docker Hub](https://hub.docker.com/u/linuxkit/)

撰寫完後，就可以透過 Moby 工具進行建構 Linux 映像檔了：
```sh
$ moby build docker-sshd.yml
Extract kernel image: linuxkit/kernel:4.9.x
Pull image: linuxkit/kernel:4.9.x
...
Create outputs:
  docker-sshd-kernel docker-sshd-initrd.img docker-sshd-cmdline
  docker-sshd.iso
```

完成後會看到以下幾個檔案：
* docker-sshd-kernel: 為 RAW Kernel 映像檔.
* docker-sshd-initrd.img: 為初始化 RAW Disk 檔案.
* docker-sshd-cmdline: Command line options 檔案.
* docker-sshd.iso: Docker SSHD ISO 格式映像檔.

### 測試映像檔
當完成建構映像檔後，就可以透過一些工具來進行測試，這邊採用 [xhyve](https://github.com/mist64/xhyve) 來執行實例，首先透過 Git 取得 xhyve repos，並建構與安裝：
```sh
$ git clone https://github.com/mist64/xhyve
$ cd xhyve
$ make && cp build/xhyve /usr/local/bin/
$ xhyve
Usage: xhyve [-behuwxMACHPWY] [-c vcpus] [-g <gdb port>] [-l <lpc>]
             [-m mem] [-p vcpu:hostcpu] [-s <pci>] [-U uuid] -f <fw>
```
> xhyve 是 FreeBSD 虛擬化技術 bhyve 的 OS X 版本，是以  [Hypervisor.framework](https://developer.apple.com/library/mac/documentation/DriversKernelHardware/Reference/Hypervisor/index.html) 為基底的上層工具，這是除了 VirtualBox 與 VMwar 的另外選擇，並且該工具非常的輕巧，只有幾 KB 的容量。

接著撰寫 xhyve 腳本來啟動映像檔：
```sh
#!/bin/sh

KERNEL="docker-sshd-kernel"
INITRD="docker-sshd-initrd.img"
CMDLINE="console=ttyS0 console=tty0 page_poison=1"

MEM="-m 1G"
PCI_DEV="-s 0:0,hostbridge -s 31,lpc"
LPC_DEV="-l com1,stdio"
ACPI="-A"
#SMP="-c 2"

# sudo if you want networking enabled
NET="-s 2:0,virtio-net"

xhyve $ACPI $MEM $SMP $PCI_DEV $LPC_DEV $NET -f kexec,$KERNEL,$INITRD,"$CMDLINE"
```
> 修改`KERNEL`與`INITRD`為 docker-sshd 的映像檔。

完成後就可以進行啟動測試：
```
$ chmod u+x run.sh
$ sudo ./run.sh
Welcome to LinuxKit

                        ##         .
                  ## ## ##        ==
               ## ## ## ## ##    ===
           /"""""""""""""""""\___/ ===
      ~~~ {~~ ~~~~ ~~~ ~~~~ ~~~ ~ /  ===- ~~~
           \______ o           __/
             \    \         __/
              \____\_______/
...
/ # ls
bin         etc         lib         root        srv         usr
containers  home        media       run         sys         var
dev         init        proc        sbin        tmp
/ # ip
...
4: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP qlen 1000
    inet 192.168.64.4/24 brd 192.168.64.255 scope global eth0
       valid_lft forever preferred_lft forever
14: docker0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN
    inet 172.17.0.1/16 scope global docker0
       valid_lft forever preferred_lft forever
```

### 驗證映像檔服務
當看到上述結果後，表示作業系統開啟無誤，這時候我們要測試系統服務是否正常，首先透過 SSH 來進行測試，在剛剛新增的 ssh public key 主機上執行以下：
```
$ ssh root@192.168.64.4
moby-aa16c789d03b:~# uname -r
4.9.25-linuxkit

moby-aa16c789d03b:~# exit
```

查看 Docker 是否啟動：
```
moby-aa16c789d03b:~# netstat -xp
Active UNIX domain sockets (w/o servers)
Proto RefCnt Flags       Type       State         I-Node PID/Program name    Path
unix  2      [ ]         DGRAM                     33822 606/dhcpcd
unix  3      [ ]         STREAM     CONNECTED      33965 748/ntpd: dns engin
unix  3      [ ]         STREAM     CONNECTED      33960 747/ntpd: ntp engin
unix  3      [ ]         STREAM     CONNECTED      33964 747/ntpd: ntp engin
unix  3      [ ]         STREAM     CONNECTED      33959 642/ntpd
unix  3      [ ]         STREAM     CONNECTED      34141 739/dockerd
unix  3      [ ]         STREAM     CONNECTED      34142 751/docker-containe /var/run/docker/libcontainerd/docker-containerd.sock
```

最後關閉虛擬機可以透過以下指令完成：
```
moby-aa16c789d03b:~# halt
Terminated
```
