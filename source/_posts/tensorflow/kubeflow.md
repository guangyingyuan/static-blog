---
title: 利用 Kubeflow 來管理 TensorFlow 訓練
date: 2018-3-15 17:08:54
layout: page
categories:
- TensorFlow
tags:
- Kubernetes
- TensorFlow
- GPU
- DL/ML
---
[Kubeflow](https://github.com/kubeflow/kubeflow) 是 Google 開源的機器學習工具，目標是簡化在 Kubernetes 上運行機器學習的過程，使之更簡單、可攜帶與可擴展。Kubeflow 目標不是在於重建其他服務，而是提供一個最佳開發系統來部署到各種基礎設施架構中，另外由於使用 Kubernetes 來做為基礎，因此只要有 Kubernetes 的地方，都能夠執行 Kubeflow。

<!--more-->

該工具能夠建立以下幾項功能：
* 用於建議與管理互動式 Jupyter notebook 的 JupyterHub。
* 可以設定使用 CPU 或 GPU，並透過單一設定調整單個叢集大小的 Tensorflow Training Controller。
* 用 TensorFlow Serving 容器來提供模型服務。

Kubeflow 目標是透過 Kubernetes 的特性使機器學習更加簡單與快速：
* 在不同基礎設施上實現簡單、可重複的攜帶性部署(Laptop <-> ML rig <-> Training cluster <-> Production cluster)。
* 部署與管理松耦合的微服務。
* 根據需求進行縮放。

## 節點資訊
本次安裝作業系統採用`Ubuntu 16.04 Server`，測試環境為實體機器：

| IP Address    | Role      | vCPU | RAM | Extra Device |
|---------------|-----------|------|-----|--------------|
| 172.22.132.51 | gpu-node1 | 8    | 16G | GTX 1060 3G  |
| 172.22.132.52 | gpu-node2 | 8    | 16G | GTX 1060 3G  |
| 172.22.132.53 | master1   | 8    | 16G | 無           |

## 事前準備
使用 Kubeflow 之前，需要確保以下條件達成：
* 所有節點正確安裝指定版本的 NVIDIA driver、CUDA、Docker、NVIDIA Docker，請參考 [安裝 Nvidia Docker 2](https://kairen.github.io/2018/02/17/container/docker-nvidia-install/)。
* 所有節點以 kubeadm 部署成 Kubernetes v1.9+ 叢集，請參考 [用 kubeadm 部署 Kubernetes 叢集](https://kairen.github.io/2016/09/29/kubernetes/deploy/kubeadm/)。
* Kubernetes 叢集需要安裝 NVIDIA Device Plugins，請參考 [安裝 Kubernetes NVIDIA Device Plugins](https://kairen.github.io/2018/03/01/kubernetes/k8s-device-plugin/)。
* 建立 NFS server 並在 Kubernetes 節點安裝 NFS common，然後利用 Kubernetes 建立 PV 提供給 Kubeflow 使用：

```sh
# 在 master 執行
$ sudo apt-get update && sudo apt-get install -y nfs-server
$ sudo mkdir /nfs-data
$ echo "/nfs-data *(rw,sync,no_root_squash,no_subtree_check)"
$ sudo /etc/init.d/nfs-kernel-server restart

# 在 node 執行
$ sudo apt-get update && sudo apt-get install -y nfs-common
```

* 安裝 `ksonnet v0.8.0`(latest or dev build 有問題)，請參考以下：

```sh
$ wget https://github.com/ksonnet/ksonnet/releases/download/v0.8.0/ks_0.8.0_linux_amd64.tar.gz
$ tar xvf ks_0.8.0_linux_amd64.tar.gz
$ sudo cp ks_0.8.0_linux_amd64/ks /usr/local/bin/
$ ks version
ksonnet version: 0.8.0
jsonnet version: v0.9.5
client-go version: v1.6.8-beta.0+$Format:%h$
```

## 部署 Kubeflow
本節將說明如何利用 ksonnet 來部署 Kubeflow 到 Kubernetes 叢集中。首先初始化 ksonnet 應用程式目錄：
```sh
$ ks init my-kubeflow
```
> 如果遇到以下問題的話，可以自己建立 GitHub Token 來存取 GitHub API，請參考 [Github rate limiting errors](https://ksonnet.io/docs/tutorial#troubleshooting-github-rate-limiting-errors)。
```sh
ERROR GET https://api.github.com/repos/ksonnet/parts/commits/master: 403 API rate limit exceeded for 122.146.93.152.
```

接著安裝 Kubeflow 套件至應用程式目錄：
```sh
$ cd my-kubeflow
$ ks registry add kubeflow github.com/kubeflow/kubeflow/tree/master/kubeflow
$ ks pkg install kubeflow/core
$ ks pkg install kubeflow/tf-serving
$ ks pkg install kubeflow/tf-job
```

然後建立 Kubeflow 核心元件，該元件包含 JupyterHub 與 TensorFlow job controller：
```sh
$ kubectl create namespace kubeflow
$ kubectl create clusterrolebinding tf-admin --clusterrole=cluster-admin --serviceaccount=default:tf-job-operator
$ ks generate core kubeflow-core --name=kubeflow-core --namespace=kubeflow

# 啟動收集匿名使用者使用量資訊，如果不想開啟則忽略
$ ks param set kubeflow-core reportUsage true
$ ks param set kubeflow-core usageId $(uuidgen)

# 部署 Kubeflow
$ ks param set kubeflow-core jupyterHubServiceType LoadBalancer
$ ks apply default -c kubeflow-core
```
> 詳細使用量資訊請參考 [Usage Reporting
](https://github.com/kubeflow/kubeflow/blob/master/user_guide.md#usage-reporting)。

完成後檢查 Kubeflow 元件部署結果：
```sh
$ kubectl -n kubeflow get po -o wide
NAME                                  READY     STATUS    RESTARTS   AGE       IP               NODE
ambassador-7956cf5c7f-6hngq           2/2       Running   0          34m       10.244.41.132    kube-gpu-node1
ambassador-7956cf5c7f-jgxnd           2/2       Running   0          34m       10.244.152.134   kube-gpu-node2
ambassador-7956cf5c7f-jww2d           2/2       Running   0          34m       10.244.41.133    kube-gpu-node1
spartakus-volunteer-8c659d4f5-bg7kn   1/1       Running   0          34m       10.244.152.135   kube-gpu-node2
tf-hub-0                              1/1       Running   0          34m       10.244.152.133   kube-gpu-node2
tf-job-operator-78757955b-2jbdh       1/1       Running   0          34m       10.244.41.131    kube-gpu-node1
```

這時候就可以登入 Jupyter Notebook，但這邊需要修改 Kubernetes Service，透過以下指令進行：
```sh
$ kubectl -n kubeflow get svc -o wide
NAME               TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE       SELECTOR
ambassador         ClusterIP   10.101.157.91    <none>        80/TCP     45m       service=ambassador
ambassador-admin   ClusterIP   10.107.24.138    <none>        8877/TCP   45m       service=ambassador
k8s-dashboard      ClusterIP   10.111.128.104   <none>        443/TCP    45m       k8s-app=kubernetes-dashboard
tf-hub-0           ClusterIP   None             <none>        8000/TCP   45m       app=tf-hub
tf-hub-lb          ClusterIP   10.105.47.253    <none>        80/TCP     45m       app=tf-hub

# 修改 svc 將 Type 修改成 LoadBalancer，並且新增 externalIPs 指定為 Master IP。
$ kubectl -n kubeflow edit svc tf-hub-lb
...
spec:
  type: LoadBalancer
  externalIPs:
  - 172.22.132.41
...
```

## 測試 Kubeflow
開始測試前先建立一個 NFS PV 來提供給 Kubeflow Jupyter 使用：
```sh
$ cat <<EOF | kubectl create -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-pv
spec:
  capacity:
    storage: 20Gi
  accessModes:
    - ReadWriteOnce
  nfs:
    server: 172.22.132.41
    path: /nfs-data
EOF
```

完成後連接 `http://Master_IP`，並輸入`任意帳號密碼`進行登入。

![](/images/kubeflow/1.png)

登入後點選`Start My Server`按鈕來建立 Server 的 Spawner options，這邊注意預設 image 為以下兩種：
* CPU：gcr.io/kubeflow-images-staging/tensorflow-notebook-cpu。
* GPU：gcr.io/kubeflow-images-staging/tensorflow-notebook-gpu。

> P.S. 這邊建議使用以下映像檔做測試使用：
* gcr.io/kubeflow/tensorflow-notebook-cpu:latest
* gcr.io/kubeflow/tensorflow-notebook-gpu:latest

> 如果使用 GPU 請執行以下指令確認是否可被分配資源：
```sh
$ kubectl get nodes "-o=custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu"
NAME               GPU
kube-gpu-master1   <none>
kube-gpu-node1     1
kube-gpu-node2     1
```

最後點選`Spawn`來完成建立 Server，如下圖所示：

![](/images/kubeflow/2.png)

接著等 Kubernetes 下載映像檔後，就會正常啟動，如下圖所示：

![](/images/kubeflow/3.png)

當正常啟動後，點選`New > Python 3`建立一個 Notebook 並貼上以下範例程式：
```python
from __future__ import print_function

import tensorflow as tf

hello = tf.constant('Hello TensorFlow!')
s = tf.Session()
print(s.run(hello))
```

正確執行會如以下圖所示：

![](/images/kubeflow/4.png)
> 若想關閉叢集的話，可以點選`Control Plane`。

另外由於 Kubeflow 會安裝 TF Operator 來管理 TFJob，這邊可以透過 Kubernetes 來手動建立 Job：
```sh
$ kubectl create -f https://raw.githubusercontent.com/kubeflow/tf-operator/master/examples/tf_job.yaml
$ kubectl get po
NAME                              READY     STATUS    RESTARTS   AGE
example-job-ps-qq6x-0-pdx7v       1/1       Running   0          5m
example-job-ps-qq6x-1-2mpfp       1/1       Running   0          5m
example-job-worker-qq6x-0-m5fm5   1/1       Running   0          5m
```

若想從 Kubernetes 叢集刪除 Kubeflow 相關元件的話，可執行下列指令達成：
```sh
$ ks delete default -c kubeflow-core
```
