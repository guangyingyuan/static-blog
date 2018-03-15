---
title: Kubernetes NVIDIA Device Plugins
date: 2018-3-01 17:08:54
layout: page
categories:
- Kubernetes
tags:
- Kubernetes
- GPU
---
[Device Plugins](https://kubernetes.io/docs/concepts/cluster-administration/device-plugins/) 是 Kubernetes v1.8 版本開始加入的 Alpha 功能，目標是結合 Extended Resource 來支援 GPU、FPGA、高效能 NIC、InfiniBand 等硬體設備介接的插件，這樣好處在於硬體供應商不需要修改 Kubernetes 核心程式，只需要依據 [Device Plugins 介面](https://github.com/kubernetes/community/blob/master/contributors/design-proposals/resource-management/device-plugin.md)來實作特定硬體設備插件，就能夠提供給 Kubernetes Pod 使用。而本篇會稍微提及 Device Plugin 原理，並說明如何使用 NVIDIA device plugin。

P.S. 傳統的`alpha.kubernetes.io/nvidia-gpu`將於 1.11 版本移除，因此與 GPU 相關的排程與部署原始碼都將從 Kubernetes 核心移除。
<!--more-->

## Device Plugins 原理
Device  Plugins 主要提供了一個 [gRPC 介面](https://github.com/kubernetes/community/blob/master/contributors/design-proposals/resource-management/device-plugin.md)來給廠商實現`ListAndWatch()`與`Allocate()`等 gRPC 方法，並監聽節點的`/var/lib/kubelet/device-plugins/`目錄中的 gRPC Server Unix Socket，這邊可以參考官方文件 [Device Plugins](https://kubernetes.io/docs/concepts/cluster-administration/device-plugins/)。一旦啟動 Device Plugins 時，透過 Kubelet Unix Socket 註冊，並提供該 plugin 的 Unix Socket 名稱、API 版本號與插件資源名稱(vendor-domain/resource，例如 nvidia.com/gpu)，接著 Kubelet 會將這些曝露到 Node 狀態以便 Scheduler 使用。

Unix Socket 範例：
```sh
$ ls /var/lib/kubelet/device-plugins/
kubelet_internal_checkpoint  kubelet.sock  nvidia.sock
```

一些 Device Plugins 列表：
- [NVIDIA GPU](https://github.com/NVIDIA/k8s-device-plugin)
- [RDMA](https://github.com/hustcat/k8s-rdma-device-plugin)
- [Kubevirt](https://github.com/kubevirt/kubernetes-device-plugins)
- [SFC](https://github.com/vikaschoudhary16/sfc-device-plugin)

## 節點資訊
本次安裝作業系統採用`Ubuntu 16.04 Server`，測試環境為實體機器：

| IP Address    | Role      | vCPU | RAM | Extra Device |
|---------------|-----------|------|-----|--------------|
| 172.22.132.51 | gpu-node1 | 8    | 16G | GTX 1060 3G  |
| 172.22.132.52 | gpu-node2 | 8    | 16G | GTX 1060 3G  |
| 172.22.132.53 | master1   | 8    | 16G | 無           |

## 事前準備
安裝 Device Plugin 前，需要確保以下條件達成：
* 所有節點正確安裝指定版本的 NVIDIA driver、CUDA、Docker、NVIDIA Docker。請參考 [安裝 Nvidia Docker 2](https://kairen.github.io/2018/02/17/container/docker-nvidia-install/)。
* 所有節點以 kubeadm 部署成 Kubernetes v1.9+ 叢集。請參考 [用 kubeadm 部署 Kubernetes 叢集](https://kairen.github.io/2016/09/29/kubernetes/deploy/kubeadm/)

## 安裝 NVIDIA Device Plugin
若上述要求以符合，再開始前需要在`每台 GPU worker 節點`修改`/lib/systemd/system/docker.service`檔案，將 Docker default runtime 改成 nvidia，依照以下內容來修改：
```sh
...
ExecStart=/usr/bin/dockerd -H fd:// --default-runtime=nvidia
...
```
> 這邊也可以修改`/etc/docker/daemon.json`檔案，請參考 [Configure and troubleshoot the Docker daemon](https://docs.docker.com/config/daemon/)。

完成後儲存，並重新啟動 Docker：
```sh
$ sudo systemctl daemon-reload && sudo systemctl restart docker
```

接著由於 v1.9 版本的 Device Plugins 還是處於 Alpha 中，因此需要手動修改`每台 GPU worker 節點`的 kubelet drop-in `/etc/systemd/system/kubelet.service.d/10-kubeadm.conf`檔案，這邊在`KUBELET_CERTIFICATE_ARGS`加入一行 args：
```sh
...
Environment="KUBELET_EXTRA_ARGS=--feature-gates=DevicePlugins=true"
...
```

完成後儲存，並重新啟動 kubelet：
```sh
$ sudo systemctl daemon-reload && sudo systemctl restart kubelet
```

確認上述完成，接著在`Master`節點安裝 NVIDIA Device Plugins，透過以下方式來進行：
```sh
$ kubectl create -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v1.9/nvidia-device-plugin.yml
daemonset "nvidia-device-plugin-daemonset" created

$ kubectl -n kube-system get po -o wide
NAME                                       READY     STATUS    RESTARTS   AGE       IP               NODE
...
nvidia-device-plugin-daemonset-bncw2       1/1       Running   0          2m        10.244.41.135    kube-gpu-node1
nvidia-device-plugin-daemonset-ddnhd       1/1       Running   0          2m        10.244.152.132   kube-gpu-node2
```

## 測試 GPU
當 NVIDIA Device Plugins 部署完成後，即可建立一個簡單範例來進行測試：
```sh
$ cat <<EOF | kubectl create -f -
apiVersion: v1
kind: Pod
metadata:
  name: gpu-pod
spec:
  restartPolicy: Never
  containers:
  - image: nvidia/cuda
    name: cuda
    command: ["nvidia-smi"]
    resources:
      limits:
        nvidia.com/gpu: 1
EOF
pod "gpu-pod" created

$ kubectl get po -a -o wide
NAME      READY     STATUS      RESTARTS   AGE       IP              NODE
gpu-pod   0/1       Completed   0          50s       10.244.41.136   kube-gpu-node1

$ kubectl logs gpu-pod
Thu Mar 15 07:28:45 2018
+-----------------------------------------------------------------------------+
| NVIDIA-SMI 390.30                 Driver Version: 390.30                    |
|-------------------------------+----------------------+----------------------+
| GPU  Name        Persistence-M| Bus-Id        Disp.A | Volatile Uncorr. ECC |
| Fan  Temp  Perf  Pwr:Usage/Cap|         Memory-Usage | GPU-Util  Compute M. |
|===============================+======================+======================|
|   0  GeForce GTX 106...  Off  | 00000000:01:00.0 Off |                  N/A |
|  0%   41C    P8    10W / 120W |      0MiB /  3019MiB |      1%      Default |
+-------------------------------+----------------------+----------------------+

+-----------------------------------------------------------------------------+
| Processes:                                                       GPU Memory |
|  GPU       PID   Type   Process name                             Usage      |
|=============================================================================|
|  No running processes found                                                 |
+-----------------------------------------------------------------------------+
```

從上面結果可以看到 Kubernetes Pod 正確的使用到 NVIDIA GPU，這邊也可以利用 TensorFlow 來進行測試，新增一個檔案`tf-gpu-dp.yml`加入以下內容：
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tf-gpu
spec:
  replicas: 1
  selector:
    matchLabels:
      app: tf-gpu
  template:
    metadata:
     labels:
       app: tf-gpu
    spec:
      containers:
      - name: tensorflow
        image: tensorflow/tensorflow:latest-gpu
        ports:
        - containerPort: 8888
        resources:
          limits:
            nvidia.com/gpu: 1
```

利用 kubectl 建立 Deployment，並曝露 Jupyter port：
```sh
$ kubectl create -f tf-gpu-dp.yml
deployment "tf-gpu" created

$ kubectl expose deploy tf-gpu --type LoadBalancer --external-ip=172.22.132.53 --port 8888 --target-port 8888
service "tf-gpu" exposed

$ kubectl get po,svc -o wide
NAME                         READY     STATUS    RESTARTS   AGE       IP               NODE
po/tf-gpu-6f9464f94b-pq8t9   1/1       Running   0          1m        10.244.152.133   kube-gpu-node2

NAME             TYPE           CLUSTER-IP       EXTERNAL-IP     PORT(S)          AGE       SELECTOR
svc/kubernetes   ClusterIP      10.96.0.1        <none>          443/TCP          23h       <none>
svc/tf-gpu       LoadBalancer   10.105.104.183   172.22.132.53   8888:30093/TCP   12s       app=tf-gpu
```
> 確認無誤後，透過 logs 指令取得 token，並登入`Jupyter Notebook`，這邊 IP 為 <master1_ip>:8888。

這邊執行一個簡單範例，並在用 logs 指令查看就能看到 Pod 透過 NVIDIA Device Plugins 使用 GPU：
```sh
$ kubectl logs -f tf-gpu-6f9464f94b-pq8t9
...
2018-03-15 07:37:22.022052: I tensorflow/core/platform/cpu_feature_guard.cc:140] Your CPU supports instructions that this TensorFlow binary was not compiled to use: AVX2 FMA
2018-03-15 07:37:22.155254: I tensorflow/stream_executor/cuda/cuda_gpu_executor.cc:898] successful NUMA node read from SysFS had negative value (-1), but there must be at least one NUMA node, so returning NUMA node zero
2018-03-15 07:37:22.155565: I tensorflow/core/common_runtime/gpu/gpu_device.cc:1212] Found device 0 with properties:
name: GeForce GTX 1060 3GB major: 6 minor: 1 memoryClockRate(GHz): 1.7845
pciBusID: 0000:01:00.0
totalMemory: 2.95GiB freeMemory: 2.88GiB
2018-03-15 07:37:22.155586: I tensorflow/core/common_runtime/gpu/gpu_device.cc:1312] Adding visible gpu devices: 0
2018-03-15 07:37:22.346590: I tensorflow/core/common_runtime/gpu/gpu_device.cc:993] Creating TensorFlow device (/job:localhost/replica:0/task:0/device:GPU:0 with 2598 MB memory) -> physical GPU (device: 0, name: GeForce GTX 1060 3GB, pci bus id: 0000:01:00.0, compute capability: 6.1)
```

最後因為目前 Pod 會綁整張 GPU 來使用，因此當無多餘顯卡時就讓 Pod 處於 Pending：
```sh
$ kubectl scale deploy tf-gpu --replicas=3
$ kubectl get po -o wide
NAME                      READY     STATUS    RESTARTS   AGE       IP               NODE
tf-gpu-6f9464f94b-42xcf   0/1       Pending   0          4s        <none>           <none>
tf-gpu-6f9464f94b-nxdw5   1/1       Running   0          12s       10.244.41.138    kube-gpu-node1
tf-gpu-6f9464f94b-pq8t9   1/1       Running   0          5m        10.244.152.133   kube-gpu-node2
```
