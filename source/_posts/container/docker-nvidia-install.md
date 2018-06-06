---
title: 安裝 NVIDIA Docker 2 來讓容器使用 GPU
date: 2018-02-17 17:08:54
layout: page
categories:
- Container
tags:
- Container
- Docker
- NVIDIA GPU
---
本篇主要介紹如何使用 [NVIDIA Docker v2](https://github.com/NVIDIA/nvidia-docker) 來讓容器使用 GPU，過去 NVIDIA Docker v1 需要使用 nvidia-docker 來取代 Docker 執行 GPU image，或是透過手動掛載 NVIDIA driver 與 CUDA 來使 Docker 能夠編譯與執行 GPU 應用程式 image，而新版本的 Docker 則可以透過 --runtime 來選擇使用 NVIDIA Docker v2 的 Runtime 來執行 GPU 應用。

<!--more-->

安裝前需要確認滿足以下幾點：
* GNU/Linux x86_64 with kernel version > 3.10
* Docker CE or EE == v18.03.1
* NVIDIA GPU with Architecture > Fermi (2.1)
* NVIDIA drivers ~= 361.93 (untested on older versions)

首先透過 APT 安裝 Docker CE or EE v17.12 版本：
```sh
$ curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
$ echo "deb [arch=amd64] https://download.docker.com/linux/ubuntu xenial edge" | sudo tee /etc/apt/sources.list.d/docker.list
$ sudo apt-get update && sudo apt-get install -y docker-ce=18.03.1~ce-0~ubuntu
```

接著透過 APT 安裝 NVIDIA Driver(v390.30) 與 CUDA 9.1：
```sh
$ wget http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1604/x86_64/cuda-repo-ubuntu1604_9.1.85-1_amd64.deb
$ sudo dpkg -i cuda-repo-ubuntu1604_9.1.85-1_amd64.deb
$ sudo apt-key adv --fetch-keys http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1604/x86_64/7fa2af80.pub
$ sudo apt-get update && sudo apt-get install -y cuda
```

測試 NVIDIA Dirver 與 CUDA 是否有安裝完成：
```sh
$ cat /usr/local/cuda/version.txt
CUDA Version 9.1.85

$ sudo nvidia-smi
Tue Mar 13 06:10:39 2018
+-----------------------------------------------------------------------------+
| NVIDIA-SMI 390.30                 Driver Version: 390.30                    |
|-------------------------------+----------------------+----------------------+
| GPU  Name        Persistence-M| Bus-Id        Disp.A | Volatile Uncorr. ECC |
| Fan  Temp  Perf  Pwr:Usage/Cap|         Memory-Usage | GPU-Util  Compute M. |
|===============================+======================+======================|
|   0  GeForce GTX 106...  Off  | 00000000:01:00.0 Off |                  N/A |
|  0%   33C    P0    15W / 120W |      0MiB /  3019MiB |      2%      Default |
+-------------------------------+----------------------+----------------------+

+-----------------------------------------------------------------------------+
| Processes:                                                       GPU Memory |
|  GPU       PID   Type   Process name                             Usage      |
|=============================================================================|
|  No running processes found                                                 |
+-----------------------------------------------------------------------------+
```

確認上述無誤後，接著安裝 NVIDIA Docker v2，這邊透過 APT 來進行安裝：
```sh
$ curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
$ curl -s -L https://nvidia.github.io/nvidia-docker/ubuntu16.04/amd64/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list
$ sudo apt-get update && sudo apt-get install -y nvidia-docker2=2.0.3+docker18.03.1-1
$ sudo pkill -SIGHUP dockerd
```

測試 NVIDIA runtime，這邊下載 NVIDIA image 來進行測試：
```sh
$ docker run --runtime=nvidia --rm nvidia/cuda nvidia-smi
...
+-----------------------------------------------------------------------------+
| NVIDIA-SMI 390.30                 Driver Version: 390.30                    |
|-------------------------------+----------------------+----------------------+
| GPU  Name        Persistence-M| Bus-Id        Disp.A | Volatile Uncorr. ECC |
| Fan  Temp  Perf  Pwr:Usage/Cap|         Memory-Usage | GPU-Util  Compute M. |
|===============================+======================+======================|
|   0  GeForce GTX 106...  Off  | 00000000:01:00.0 Off |                  N/A |
|  0%   35C    P0    15W / 120W |      0MiB /  3019MiB |      2%      Default |
+-------------------------------+----------------------+----------------------+

+-----------------------------------------------------------------------------+
| Processes:                                                       GPU Memory |
|  GPU       PID   Type   Process name                             Usage      |
|=============================================================================|
|  No running processes found                                                 |
+-----------------------------------------------------------------------------+
```

透過 TensorFlow GPU image 來進行測試，這邊執行後登入 IP:8888 執行簡單範例程式：
```sh
$ docker run --runtime=nvidia -it -p 8888:8888 tensorflow/tensorflow:latest-gpu
...
2018-03-13 06:44:21.719705: I tensorflow/core/common_runtime/gpu/gpu_device.cc:1212] Found device 0 with properties:
name: GeForce GTX 1060 3GB major: 6 minor: 1 memoryClockRate(GHz): 1.7845
pciBusID: 0000:01:00.0
totalMemory: 2.95GiB freeMemory: 2.88GiB
2018-03-13 06:44:21.719728: I tensorflow/core/common_runtime/gpu/gpu_device.cc:1312] Adding visible gpu devices: 0
2018-03-13 06:44:21.919097: I tensorflow/core/common_runtime/gpu/gpu_device.cc:993] Creating TensorFlow device (/job:localhost/replica:0/task:0/device:GPU:0 with 2598 MB memory) -> physical GPU (device: 0, name: GeForce GTX 1060 3GB, pci bus id: 0000:01:00.0, compute capability: 6.1)
```
