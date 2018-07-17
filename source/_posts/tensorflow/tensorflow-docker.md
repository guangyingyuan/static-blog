---
title: TensorFlow on Docker
catalog: true
date: 2016-010-01 16:23:01
categories:
- TensorFlow
tags:
- TensorFlow
- Machine Learning
- Docker
---
本篇主要整理使用 Docker 來執行 TensorFlow 的一些問題，這邊 Google 官方已經提供了相關的映像檔提供使用，因此會簡單說明安裝過程與需求。

![](/images/tf/docker-tf.png)

<!--more-->

<br>
## 環境準備
環境採用 Ubuntu 16.04 Desktop 作業系統，然後顯卡是撿朋友不要的來使用，環境硬體資源如下：

| 名稱         | 描述                  |
|-------------|-----------------------|
| CPU         | i7-4790 CPU @ 3.60GHz |
| Memory      | 32GB                  |
| GPU         | GeForce GTX 650       |

## 事前準備
開始進行 TensorFlow on Docker 之前，需要確認環境已經安裝以下驅動與軟體等。
* 系統安裝了 Docker Engine：

```sh
$ curl -fsSL "https://get.docker.com/" | sh
$ sudo iptables -P FORWARD ACCEPT
```

* 安裝最新版本 NVIDIA Driver 軟體：

```sh
$ sudo add-apt-repository -y ppa:graphics-drivers/ppa
$ sudo apt-get update
$ sudo apt-get install -y nvidia-367
$ sudo dpkg -l | grep nvidia-367
... 375.39-0ubuntu0.16.04.1 ..
```

* 編譯與安裝 nvidia-modprobe：

```sh
$ sudo apt-get install -y m4
$ git clone "https://github.com/NVIDIA/nvidia-modprobe.git"
$ cd nvidia-modprobe
$ make && sudo make install
$ sudo nvidia-modprobe -u -c=0
```

* 安裝 Nvidia Docker Plugin:

```sh
$ wget -P /tmp "https://github.com/NVIDIA/nvidia-docker/releases/download/v1.0.1/nvidia-docker_1.0.1-1_amd64.deb"
$ sudo dpkg -i /tmp/nvidia-docker*.deb && rm /tmp/nvidia-docker*.deb
$ sudo systemctl start nvidia-docker.service
$ sudo nvidia-docker run --rm nvidia/cuda nvidia-smi
...
+-----------------------------------------------------------------------------+
| NVIDIA-SMI 375.39                 Driver Version: 375.39                    |
|-------------------------------+----------------------+----------------------+
| GPU  Name        Persistence-M| Bus-Id        Disp.A | Volatile Uncorr. ECC |
| Fan  Temp  Perf  Pwr:Usage/Cap|         Memory-Usage | GPU-Util  Compute M. |
|===============================+======================+======================|
|   0  GeForce GTX 650     Off  | 0000:01:00.0     N/A |                  N/A |
| 10%   34C    P8    N/A /  N/A |    267MiB /   975MiB |     N/A      Default |
+-------------------------------+----------------------+----------------------+

+-----------------------------------------------------------------------------+
| Processes:                                                       GPU Memory |
|  GPU       PID  Type  Process name                               Usage      |
|=============================================================================|
```

## 利用 Docker 執行 TensorFlow
TensorFlow on Docker 官方已經提供了相關映像檔，這邊透過單一指令就可以取得該映像檔，並啟動提供使用，以下為只有 CPU 的版本：
```sh
$ docker run -d -p 8888:8888 --name tf-cpu tensorflow/tensorflow
$ docker logs tf-cpu
...
to login with a token:
        http://localhost:8888/?token=7ddd6ef31fed5f22696c1003a905782b9219a6ec9a19b97c
```
> 這時候就可以登入 [Jupyter notebook](http://localhost:8888)，這邊登入需要`token`後面的值。

若要支援 GPU(CUDA) 的容器的話，可以透過以下指令來提供：
```sh
$ nvidia-docker run -d -p 8888:8888 --name tf-gpu tensorflow/tensorflow:latest-gpu
$ docker logs tf-cpu
```
> 其他版本可以參考 [tags](https://hub.docker.com/r/tensorflow/tensorflow/tags/)。

## 利用 Docker 提供 Serving
TensorFlow Serving 是靈活、高效能的機器學習模型服務系統，是專門為生產環境而設計的，它可以很簡單部署新的演算法與實驗來提供同樣的架構與 API 進行服務。

首先我們下載官方寫好的 [Dockerfile ](https://raw.githubusercontent.com/tensorflow/serving/master/tensorflow_serving/tools/docker/Dockerfile.devel) 來進行建置：
```sh
$ mkdir serving && cd serving
$ wget "https://raw.githubusercontent.com/tensorflow/serving/master/tensorflow_serving/tools/docker/Dockerfile.devel"
$ sed -i 's/BAZEL_VERSION.*0.4.2/BAZEL_VERSION 0.4.5/g' Dockerfile.devel
$ docker build --pull -t kyle/serving:0.1.0 -f Dockerfile.devel .
```

建置完成映像檔後，透過以下指令執行，並在容器內建置 Serving：
```sh
$ docker run -itd --name=tf-serving kyle/serving:0.1.0
$ docker exec -ti tf-serving bash
root@459a89a3cf5a$ git clone --recurse-submodules "https://github.com/tensorflow/serving"
root@459a89a3cf5a$ cd serving/tensorflow
root@459a89a3cf5a$ ./configure
root@459a89a3cf5a$ cd .. && bazel build -c opt tensorflow_serving/...
```

當建置完 Serving 後，就可以透過以下指令來確認是否正確：
```sh
root@459a89a3cf5a$ bazel-bin/tensorflow_serving/model_servers/tensorflow_model_server
usage: bazel-bin/tensorflow_serving/model_servers/tensorflow_model_server
Flags:
	--port=8500                      	int32	port to listen on
	--enable_batching=false
...
```

接著使用 Inception v3 模型來提供服務，透過以下步驟來完成：
```sh
root@459a89a3cf5a$ curl -O "http://download.tensorflow.org/models/image/imagenet/inception-v3-2016-03-01.tar.gz"
root@459a89a3cf5a$ tar xzf inception-v3-2016-03-01.tar.gz
root@459a89a3cf5a$ ls inception-v3
README.txt  checkpoint  model.ckpt-157585

root@459a89a3cf5a$ bazel-bin/tensorflow_serving/example/inception_saved_model --checkpoint_dir=inception-v3 --output_dir=inception-export
Successfully exported model to inception-export

root@459a89a3cf5a$ ls inception-export
1
```

當完成匯入後離開容器，並 commit 成新版本映像檔：
```sh
$ docker commit tf-serving kyle/serving-inception:0.1.0
$ docker images
REPOSITORY               TAG                 IMAGE ID            CREATED             SIZE
kyle/serving-inception   0.1.0               1d866ff60d38        3 minutes ago       5.55 GB
```

接著執行剛 commit 的映像檔，並啟動 Serving 服務：
```sh
$ docker run -it kyle/serving-inception:0.1.0
root@5b9a89eeef5a$ cd serving
root@5b9a89eeef5a$ bazel-bin/tensorflow_serving/model_servers/tensorflow_model_server --port=9000 --model_name=inception --model_base_path=inception-export &> inception_log &
[1] 15
```

最後透過 `inception_client.py` 來測試功能：
```sh
root@5b9a89eeef5a$ curl "https://s-media-cache-ak0.pinimg.com/736x/32/00/3b/32003bd128bebe99cb8c655a9c0f00f5.jpg" --output rabbit.jpg
root@5b9a89eeef5a$ bazel-bin/tensorflow_serving/example/inception_client --server=localhost:9000 --image=rabbit.jpg

outputs {
  key: "classes"
  value {
    dtype: DT_STRING
    tensor_shape {
      dim {
        size: 1
      }
      dim {
        size: 5
      }
    }
    string_val: "hare"
    string_val: "wood rabbit, cottontail, cottontail rabbit"
    string_val: "Angora, Angora rabbit"
    string_val: "mouse, computer mouse"
    string_val: "gazelle"
  }
}
outputs {
  key: "scores"
  value {
    dtype: DT_FLOAT
    tensor_shape {
      dim {
        size: 1
      }
      dim {
        size: 5
      }
    }
    float_val: 10.3059120178
    float_val: 8.19226741791
    float_val: 4.00839996338
    float_val: 2.34308481216
    float_val: 2.00992465019
  }
}
```
