---
title: Ubuntu 16.04 安裝 TensorFlow GPU GTX 1060
catalog: true
date: 2017-03-12 16:23:01
categories:
- TensorFlow
tags:
- TensorFlow
- Machine Learning
- Ubuntu
---
本篇主要因為自己買了一片`Nvidia GTX 1060 6G`顯卡，但是購買至今只用來玩過一個遊戲，因此才拿來試跑 TensorFlow。

<!--more-->

本次安裝硬體與規格如下：
* 作業系統: Ubuntu 16.04 Desktop
* GPU: GeForce® GTX 1060 6G
* NVIDIA Driver: nvidia-367
* Python: 2.7+
* TensorFlow: r1.0.1
* CUDA: v8.0
* cuDNN: v5.1

# 環境部署
如果要安裝 TensorFlow with GPU support 的話，需要滿足以下幾點：
* Nvidia Driver.
* 已安裝 CUDA® Toolkit 8.0.
* 已安裝 cuDNN v5.1.
* GPU card with CUDA Compute Capability 6.1(GTX 10-series).
* libcupti-dev 函式庫.

## Nvidia Driver 安裝
由於預設 Ubuntu 的 Nvidia 版本比較舊，或者並沒有安裝相關驅動，因此這邊需要安裝顯卡對應的版本才能夠正常使用，可以透過以下方式進行：
```sh
$ sudo add-apt-repository -y ppa:graphics-drivers/ppa
$ sudo apt-get update
$ sudo apt-get install -y nvidia-367
```

完成後，需重新啟動機器。

## CUDA Toolkit 8.0 安裝
由於 TensorFlow 支援 GPU 運算時，會需要使用到 CUDA Toolkit 相關功能，可以到 [CUDA Toolkit](https://developer.nvidia.com/cuda-downloads) 頁面下載，這邊會下載 Ubuntu Run file 檔案，來進行安裝：
```sh
$ wget "https://developer.nvidia.com/compute/cuda/8.0/Prod2/local_installers/cuda_8.0.61_375.26_linux-run"
$ sudo chmod u+x cuda_8.0.61_375.26_linux-run
$ ./cuda_8.0.61_375.26_linux-run

Do you accept the previously read EULA?
accept/decline/quit: accept
Install NVIDIA Accelerated Graphics Driver for Linux-x86_64 361.77?
(y)es/(n)o/(q)uit: n
Install the CUDA 8.0 Toolkit?
(y)es/(n)o/(q)uit: y
Enter Toolkit Location
[ default is /usr/local/cuda-8.0]: enter
Do you want to install a symbolic link at /usr/local/cuda?
(y)es/(n)o/(q)uit:y
Install the CUDA 8.0 Samples?
(y)es/(n)o/(q)uit:y
Enter CUDA Samples Location
[ defualt is /home/kylebai ]: enter
```
> 這邊`enter`為鍵盤直接按壓，而不是輸入 enter。

安裝完成後，編輯 Home 目錄底下的`.bashrc`檔案加入以下內容：
```sh
export PATH=${PATH}:/usr/local/cuda-8.0/bin
export LD_LIBRARY_PATH=/usr/local/cuda-8.0/lib64
```

最後 Source Bash 檔案與測試 CUDA Toolkit：
```sh
$ source .bashrc
$ sudo nvidia-smi
+-----------------------------------------------------------------------------+
| NVIDIA-SMI 375.39                 Driver Version: 375.39                    |
|-------------------------------+----------------------+----------------------+
| GPU  Name        Persistence-M| Bus-Id        Disp.A | Volatile Uncorr. ECC |
| Fan  Temp  Perf  Pwr:Usage/Cap|         Memory-Usage | GPU-Util  Compute M. |
|===============================+======================+======================|
|   0  GeForce GTX 106...  Off  | 0000:01:00.0      On |                  N/A |
| 28%   29C    P8     6W / 120W |    130MiB /  6069MiB |      0%      Default |
+-------------------------------+----------------------+----------------------+

+-----------------------------------------------------------------------------+
| Processes:                                                       GPU Memory |
|  GPU       PID  Type  Process name                               Usage      |
|=============================================================================|
|    0      1165    G   /usr/lib/xorg/Xorg                              98MiB |
|    0      1764    G   compiz                                          29MiB |
+-----------------------------------------------------------------------------+
```

## cuDNN 5.1 安裝
[NVIDIA cuDNN](https://developer.nvidia.com/rdp/cudnn-download) 是一個深度神經網路運算的 GPU 加速原函式庫，這邊需要點選前面的連結，下載`cuDNN v5.1 Library for Linux`檔案：
```sh
$ tar xvf cudnn-8.0-linux-x64-v5.1.tgz
$ sudo cp cuda/include/cudnn.h /usr/local/cuda/include/
$ sudo cp cuda/lib64/libcudnn* /usr/local/cuda/lib64/
```

## TensorFlow GPU 套件建構
本次教學將透過 [Source code](https://github.com/tensorflow/tensorflow) 建構安裝檔，再進行安裝 TensorFlow，首先安裝相依套件：
```sh
$ sudo add-apt-repository -y ppa:webupd8team/java
$ sudo apt-get update
$ sudo apt-get install -y libcupti-dev python-numpy python-dev python-setuptools python-pip python-wheel git oracle-java8-installer
$ echo "deb [arch=amd64] http://storage.googleapis.com/bazel-apt stable jdk1.8" | sudo tee /etc/apt/sources.list.d/bazel.list
$ curl -s "https://storage.googleapis.com/bazel-apt/doc/apt-key.pub.gpg" | sudo apt-key add -
$ sudo apt-get update && sudo apt-get -y install bazel
$ sudo apt-get upgrade -y bazel
```

接著取得 TensorFlow 專案原始碼，然後進入到 TensorFlow 專案目錄進行 bazel 設定：
```sh
$ git clone "https://github.com/tensorflow/tensorflow"
$ cd tensorflow
$ ./configure

...
Do you wish to build TensorFlow with CUDA support? [y/N] y
Please specify the Cuda SDK version you want to use, e.g. 7.0. [Leave empty to use system default]: 8.0
Please specify the cuDNN version you want to use. [Leave empty to use system default]: 5
Please note that each additional compute capability significantly increases your build time and binary size.
[Default is: "3.5,5.2"]: 6.1
...
Configuration finished
```
> `6.1`為 GTX 10-series 系列顯卡，其他可以查看 [CUDA GPUS](https://developer.nvidia.com/cuda-gpus)。這邊除了上述特定要輸入外，其餘都是直接鍵盤`enter`。

當完成組態後，即可透過 bazel 進行建構 pip 套件腳本：
```sh
$ bazel build --config=opt --config=cuda //tensorflow/tools/pip_package:build_pip_package
```

當腳本建構完成後，即可透過以下指令來建構 .whl 檔案：
```sh
$ bazel-bin/tensorflow/tools/pip_package/build_pip_package /tmp/tf_pkg
```

完成後，可以在`/tmp/tf_pkg`目錄底下找到安裝檔`tensorflow-1.0.1-py2-none-any.whl`，最後就可以透過 pip 來進行安裝了：
```sh
$ sudo pip install /tmp/tf_pkg/tensorflow-1.0.1-cp27-cp27mu-linux_x86_64.whl
```

## 測試安裝結果
最後透過簡單程式來驗證安裝是否成功：
```sh
$ cat <<EOF > simple.py
import tensorflow as tf

hello = tf.constant('Hello, TensorFlow!')
sess = tf.Session()
print(sess.run(hello))
EOF

$ python simple.py
...
roperties:
name: GeForce GTX 1060 6GB
major: 6 minor: 1 memoryClockRate (GHz) 1.7845
pciBusID 0000:01:00.0
Total memory: 5.93GiB
Free memory: 5.74GiB
2017-03-12 21:43:56.477084: I tensorflow/core/common_runtime/gpu/gpu_device.cc:908] DMA: 0
2017-03-12 21:43:56.477092: I tensorflow/core/common_runtime/gpu/gpu_device.cc:918] 0:   Y
2017-03-12 21:43:56.503464: I tensorflow/core/common_runtime/gpu/gpu_device.cc:977] Creating TensorFlow device (/gpu:0) -> (device: 0, name: GeForce GTX 1060 6GB, pci bus id: 0000:01:00.0)
Hello, TensorFlow!
```
> `...`部分會顯示一些 GPU 使用狀態。
