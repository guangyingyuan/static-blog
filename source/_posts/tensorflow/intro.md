---
title: TensorFlow 基本使用與分散式概念
layout: default
date: 2017-04-10 16:23:01
categories:
- TensorFlow
tags:
- TensorFlow
- Machine Learning
- Ubuntu
---
TensorFlow™ 是利用資料流圖(Data Flow Graphs)來表達數值運算的開放式原始碼函式庫。資料流圖中的節點(Nodes)被用來表示數學運算，而邊(Edges)則用來表示在節點之間互相聯繫的多維資料陣列，即張量(Tensors)。它靈活的架構讓你能夠在不同平台上執行運算，例如 PC 中的一個或多的 CPU(或GPU)、智慧手持裝置與伺服器等。TensorFlow 最初是 Google 機器智能研究所的研究員和工程師開發而成，主要用於機器學習與深度神經網路方面研究。

<!--more-->

TensorFlow 其實在意思上是要用兩個部分來解釋，Tensor 與 Flow：
* **Tensor**：是中文翻譯是`張量`，其實就是一個`n`維度的陣列或列表。如一維 Tensor 就是向量，二維 Tensor 就是矩陣等等.
* **Flow**：是指 Graph 運算過程中的資料流.

![](https://lh3.googleusercontent.com/hIViPosdbSGUpLmPnP2WqL9EmvoVOXW7dy6nztmY5NZ9_u5lumMz4sQjjsBZ2QxjyZZCIPgucD2rhdL5uR7K0vLi09CEJYY=s688)

## Data Flow Graphs
資料流圖(Data Flow Graphs)是一種有向圖的節點(Node)與邊(Edge)來描述計算過程。圖中的節點表示數學操作，亦表示資料 I/O 端點; 而邊則表示節點之間的關析，用來傳遞操作之間互相使用的多維陣列(Tensors)，而 Tensor 是在圖中流動的資料表示。一旦節點相連的邊傳來資料流，這時節點就會被分配到運算裝置上異步(節點之間)或同步(節點之內)的執行。

<center>![](https://www.tensorflow.org/images/tensors_flowing.gif)</center>

## TensorFlow 基本使用
在開始進行 TensorFlow 之前，需要了解幾個觀念：
* 使用 [tf.Graph](https://www.tensorflow.org/api_docs/python/tf/Graph) 來表示計算任務.
* 採用`tensorflow::Session`的上下文(Context)來執行圖.
* 以 Tensor 來表示所有資料，可看成擁有靜態資料類型，但有動態大小的多維陣列與列表，如 Boolean 或 String 轉成數值類型.
* 透過`tf.Variable`來維護狀態.
* 透過 feed 與 fetch 來任意操作(Arbitrary operation)給予值或從中取得資料.

TensorFlow 的圖中的節點被稱為 [op(operation)](https://www.tensorflow.org/api_docs/python/tf/Operation)。一個`op`會有 0 至多個 Tensor，而每個 Tensor 是一種類別化的多維陣列，例如把一個圖集合表示成四維浮點陣列，分別為`[batch, height, width, channels]`。

![](http://upload-images.jianshu.io/upload_images/2630831-5da81623d4661886.jpg?imageMogr2/auto-orient/strip)

利用三種不同稱呼來描述 Tensor 的維度，Shape、Rank 與 Dimension。可參考 [Rank, Shape, 和 Type](https://www.tensorflow.org/programmers_guide/dims_types)。

![](http://upload-images.jianshu.io/upload_images/2630831-3625a021343b5da3.jpg?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

一般只有 shape 能夠直接被 print，而 Tensor 則需要 Session 來提供，一般需要三個操作步驟：
1. 建立 Tensor.
2. 新增 op.
3. 建立 Session(包含一個 Graph)來執行運算.

以下是一個簡單範例，說明如何建立運算：
```py
# coding=utf-8
import tensorflow as tf

a = tf.constant(1)
b = tf.constant(2)
c = tf.constant(3)
d = tf.constant(4)
add1 = tf.add(a, b)
mul1 = tf.multiply(b, c)
add2 = tf.add(c, d)
output = tf.add(add1, mul1)

with tf.Session() as sess:
    print sess.run(output)
```

執行流程如下圖：
![](https://github.com/lienhua34/notes/raw/master/tensorflow/asserts/graph_compute_flow.jpg?_=5998853)

以下是一個簡單範例，說明如何建立多個 Graph：
```python=
# coding=utf-8
import tensorflow as tf

logs_path = './basic_tmp'

# 建立一個 graph，並建立兩個常數 op ，這些 op 稱為節點
g1 = tf.Graph()
with g1.as_default():
    a = tf.constant([1.5, 6.0])
    b = tf.constant([1.5, 3.2])
    c = a * b

with tf.Graph().as_default() as g2:
    # 建立一個 1x2 矩陣與 2x1 矩陣 op
    m1 = tf.constant([[1., 0., 2.], [-1., 3., 1.]])
    m2 = tf.constant([[3., 1.], [2., 1.], [1., 0.]])
    m3 = tf.matmul(m1, m2) # 矩陣相乘

# 在 session 執行 graph，並進行資料數據操作 `c`。
# 然後指派給 cpu 做運算
with tf.Session(graph=g1) as sess_cpu:
  with tf.device("/cpu:0"):
      writer = tf.summary.FileWriter(logs_path, graph=g1)
      print(sess_cpu.run(c))

with tf.Session(graph=g2) as sess_gpu:
  with tf.device("/gpu:0"):
      result = sess_gpu.run(m3)
      print(result)

# 使用 tf.InteractiveSession 方式來印出內容(不會實際執行)
it_sess = tf.InteractiveSession()
x = tf.Variable([1.0, 2.0])
a = tf.constant([3.0, 3.0])

# 使用初始器 initializer op 的 run() 方法初始化 'x'
x.initializer.run()
sub = tf.subtract(x, a)

print sub.eval()
it_sess.close()

```
> * 範例來至 [Basic Usage](https://www.tensorflow.org/versions/r0.10/get_started/basic_usage)。
> * 指定 Device 可以看這邊 [Using GPU](https://www.tensorflow.org/versions/r0.10/how_tos/using_gpu/).

上面範例可以看到建立了一個 Graph 的計算過程`c`，而當直接執行到`c`時，並不會真的執行運算，而是在`sess`會話建立後，並透過`sess`執行分配給 CPU 或 GPU 之類設備進行運算後，才會回傳一個節點的 Tensor，在 Python 中 Tensor 是一個 Numpy 的 ndarry 物件。

TensorFlow 也可以透過變數來維護 Graph 的執行過程狀態，這邊提供一個簡單的累加器：
```python=
# coding=utf-8
import tensorflow as tf

# 建立一個變數 counter，並初始化為 0
state = tf.Variable(0, name="counter")

# 建立一個常數 op 為 1，並用來累加 state
one = tf.constant(1)
new_value = tf.add(state, one)
update = tf.assign(state, new_value)

# 啟動 Graph 前，變數必須先被初始化(init) op
init_op = tf.global_variables_initializer()

# 啟動 Graph 來執行 op
with tf.Session() as sess:
  sess.run(init_op)
  print sess.run(state)
  # 執行 op 並更新 state
  for _ in range(3):
    sess.run(update)
    print sess.run(state)
```
> 更多細節可以查看 [Variables](https://www.tensorflow.org/programmers_guide/variables)。

另外可以利用 Fetch 方式來一次取得多個節點的 Tensor，範例如下：
```python=
# coding=utf-8
import tensorflow as tf

input1 = tf.constant(3.0)
input2 = tf.constant(2.0)
input3 = tf.constant(5.0)
intermed = tf.add(input2, input3)
mul = tf.multiply(input1, intermed)

with tf.Session() as sess:
  # 一次取得多個 Tensor
  result = sess.run([mul, intermed])
  print result
```

而當我們想要在執行 Session 時，臨時替換 Tensor 內容的話，就可以利用 TensorFlow 內建的 Feed 方法來解決：
```python=
# coding=utf-8
import tensorflow as tf

input1 = tf.placeholder(tf.float32)
input2 = tf.placeholder(tf.float32)
output = tf.multiply(input1, input2)

with tf.Session() as sess:
  # 透過 feed 來更改 op 內容，這只會在執行時有效
  print sess.run([output], feed_dict={input1:[7.], input2:[2.]})
  print sess.run([output])
```

## TensorFlow 分散式運算
本節將以 TensorFlow 分散式深度學習為例。

### gRPC
gRPC(google Remote Procedure Call) 是 Google 開發的基於 HTTP/2 和 Protocol Buffer 3 的 RPC 框架，該框架有各種常見語言的實作，如 C、Java 與 Go 等語言，提供輕鬆跨語言的呼叫。

### 概念
說明客戶端(Client)、叢集(Cluster)、工作(Job)、任務(Task)、TensorFlow 伺服器、Master 與 Worker 服務。

![](http://www.pittnuts.com/wp-content/uploads/2016/08/TFramework.png)

如圖所示，幾個流程說明如下：
* 整個系统映射到 TensorFlow 叢集.
* 參數伺服器映射到一個 Job.
* 每個模型(Model)副本映射到一個 Job.
* 每台實體運算節點映射到其 Job 中的 Task.
* 每個 Task 都有一個 TF Server，並利用 Master 服務來進行溝通與協調工作，而 Worker 服務則透過本地裝置(CPU 或 GPU)進行 TF graph 運算.

TensorFlow 叢集裡包含了一個或多個工作(Job)，每個工作又可以拆分成一個或多個任務(Task)，簡單說 Cluster 是 Job 的集合，而 Job 是 Task 的集合。叢集概念主要用在一個特定層次對象，如訓練神經網路、平行操作多台機器等，一個叢集物件可以透過`tf.train.ClusterSpec`來定義。

如上所述，TensorFlow 的叢集就是一組工作任務，每個任務是一個服務，而服務又分成`Master`與`Worker`這兩種，並提供給`Client`進行操作。

* **Client**：是用於建立 TensorFlow 計算 Graph，並建立與叢集進行互動的`tensorflow::Session`行程，一般由 Python 或 C++ 實作，單一客戶端可以同時連接多個 TF 伺服器連接，同時也能被多個 TF 伺服器連接.
* **Master Service**：是一個 RPC 服務行程，用來遠端連線一系列分散式裝置，主要提供`tensorflow::Session`介面，並負責透過 Worker Service 與工作的任務進行溝通.
* **Worker Service**：是一個可以使用本地裝置(CPU 或 GPU)對部分 Graph 進行運算的 RPC 邏輯，透過`worker_service.proto`介面來實作，所有 TensorFlow 伺服器均包含了 Worker Service 邏輯.

> **TensorFlow 伺服器**是運行`tf.train.Server`實例的行程，其為叢集一員，並有 Master 與 Worker 之分。

而 TensorFlow 的工作(Job)可拆成多個相同功能的任務(Task)，這些工作又分成`Parameter server`與`Worker`，兩者功能說明如下：

![](https://img.tipelse.com/uploads/B/6A/B6A07C1923.jpeg)

* **Parameter server(ps)**:是分散式系統縮放至工業大小機器學習的問題，它提供工作節點與伺服器節點之間的非同步與零拷貝 key-value 的溝通，並支援資料的一致性模型的分散式儲存。在 TensorFlow 中主要根據梯度更新變數，並儲存於`tf.Variable`，可理解成只儲存 TF Model 的變數，並存放 Variable 副本.

![](http://arimo.com/wp-content/uploads/2016/03/TF_Image_0.png)

* **Worker**:通常稱為計算節點，一般管理無狀態(Stateless)，且執行密集型的 Graph 運算資源，並根據變數運算梯度。存放 Graph 副本.

![](http://arimo.com/wp-content/uploads/2016/03/TF_Image_1.png)

> - [Parameter Server 詳解](http://blog.csdn.net/cyh_24/article/details/50545780)

一般對於`小型規模訓練`，這種資料與參數量不多時，可以用一個 CPU 來同時執行兩種任務。而`中型規模訓練`，資料量較大，但參數量不多時，計算梯度的工作負載較高，而參數更新負載較低，所以計算梯度交給若干個 CPU 或 GPU 去執行，而更新參數則交給一個 CPU 即可。對於`大型規模訓練`，資料與參數量多時，不僅計算梯度需要部署多個 CPU 或 GPU，連更新參數也要不說到多個 CPU 中。

然而單一節點能夠裝載的 CPU 與 GPU 是有限的，所以在大量訓練時就需要多台機器來提供運算能力的擴展。

### 分散式變數伺服器(Parameter Server)
當在較大規模的訓練時，隨著模型的變數越來越多，很可能造成單一節點因為效能問題，而無法負荷模型變數儲存與更新時，這時候就需要將變數分開到不同機器來做儲存與更新。而 TensorFlow 提供了變數伺服器的邏輯實現，並可以用多台機器來組成叢集，類似分散式儲存結構，主要用來解決變數的儲存與更新效能問題。

### 撰寫分散式程式注意概念
當我們在寫分散式程式時，需要知道使用的副本與訓練模式。

![](https://camo.githubusercontent.com/0b7a1232bd3f8861dfbccab568a30591588384dc/68747470733a2f2f7777772e74656e736f72666c6f772e6f72672f696d616765732f74656e736f72666c6f775f666967757265372e706e67)

#### In-graph 與 Between-graph 副本模式
下圖顯示兩者差異，而這邊也在進行描述。
* **In-graph**：只有一個 Clinet(主要呼叫`tf::Session`行程)，並將裡面變數與 op 指定給對應的 Job 完成，因此資料分發只由一個 Client 完成。這種方式設定簡單，其他節點只需要 join 操作，並提供一個 gRPC 位址來等待任務。但是訓練資料只在單一節點，因此要把資料分發到不同機器時，會影響平行訓練效能。可理解成所有 op 都在同一個 Graph 中，伺服器只需要做`join()`功能.
* **Between-graph**：多個獨立 Client 建立相同 Graph(包含變數)，並透過`tf.train.replica_device_setter`將這些參數映射到 ps 上，即訓練的變數儲存在 Parameter Server，而資料不用分發，資料分片(Shards)會存在個計算節點，因此個節點自己算自己的，算完後，把要更新變數告知 Parameter Server 進行更新。適合在 TB 級別的資料量使用，節省大量資料傳輸時間，也是深度學習推薦模式。

#### 同步(Synchronous)訓練與非同步(Asynchronous)訓鍊
TensorFlow 的副本擁有 in-graph 和 between-graph 模式，這兩者都支援了同步與非同步更新。本節將說明同步與非同步兩者的差異為何。
* **Synchronous**：每個 Graph 的副本讀取相同 Parameter 的值，然後平行計算梯度(gradients)，將所有計算完的梯度放在一起處理，當每次更新梯度時，需要等所以分發的資料計算完成，並回傳結果來把梯度累加計算平均，在進行更新變數。好處在於使用 loss 的下降時比較穩定，壞處就是要等最慢的分片計算時間。

> 可以利用`tf.train.SyncReplicasOptimizer`來解決這個問題(在 Between-graph 情況下)，而在 In-graph 則將所有梯度平均即可。

* **Asynchronous**：自己計算完梯度後，就去更新 paramenter，不同副本之前不會進行協調進度，因此計算資源被充分的利用。缺點是 loss 的下降不穩定。

![](http://img.blog.csdn.net/20161114005141032)

一般在資料量小，且各節點計算能力平均下，適合使用同步模式; 反之在資料量大與各節點效能差異不同時，適合用非同步。

### 簡單分散式訓練程式
TensorFlow 提供建立 Server 函式來進行測試使用，以下是建立一個分散式訓練 Server 程式`server.py`：
```python=
# coding=utf-8
import tensorflow as tf

# 定義 Cluster
cluster = tf.train.ClusterSpec({"worker": ["localhost:2222"]})

# 建立 Worker server
server = tf.train.Server(cluster,job_name="worker",task_index=0)
server.join()
```
> 也可以透過`tf.train.Server.create_local_server()` 來建立 Local Server

當確認程式沒有任何問題後，就可以透過以下方式啟動：
```shell=
$ python server.py
2017-04-10 18:19:41.953448: I tensorflow/core/common_runtime/gpu/gpu_device.cc:977] Creating TensorFlow device (/gpu:0) -> (device: 0, name: GeForce GTX 650, pci bus id: 0000:01:00.0)
2017-04-10 18:19:41.983913: I tensorflow/core/distributed_runtime/rpc/grpc_channel.cc:200] Initialize GrpcChannelCache for job local -> {0 -> localhost:2222}
2017-04-10 18:19:41.984946: I tensorflow/core/distributed_runtime/rpc/grpc_server_lib.cc:240] Started server with target: grpc://localhost:2222
```

接著我們要撰寫 Client 端來進行定義 Graph 運算的程式`client.py`：
```python=
# coding=utf-8
import tensorflow as tf

# 執行目標 Session
server_target = "grpc://localhost:2222"
logs_path = './basic_tmp'

# 指定 worker task 0 使用 CPU 運算
with tf.device("/job:worker/task:0"):
    with tf.device("/cpu:0"):
        a = tf.constant([1.5, 6.0], name='a')
        b = tf.Variable([1.5, 3.2], name='b')
        c = (a * b) + (a / b)
        d = c * a
        y = tf.assign(b, d)

# 啟動 Session
with tf.Session(server_target) as sess:
    sess.run(tf.global_variables_initializer())
    writer = tf.summary.FileWriter(logs_path, graph=tf.get_default_graph())
    print(sess.run(y))
```

完成後即可透過以下指令測試：
```python=
$ python client.py
[   4.875       126.45000458]
```

### 線性迴歸訓練程式
上面範例提供了很簡單的 Client 與 Server 運算操作。而這邊建立一個 Between-graph 執行程式`bg_dist.py`：
```python=
# coding=utf-8
import tensorflow as tf
import numpy as np

parameter_servers = ["localhost:2222"]
workers = ["localhost:2223", "localhost:2224"]

tf.app.flags.DEFINE_string("job_name", "", "輸入 'ps' 或是 'worker'")
tf.app.flags.DEFINE_integer("task_index", 0, "Job 的任務 index")
FLAGS = tf.app.flags.FLAGS


def main(_):

    cluster = tf.train.ClusterSpec({"ps": parameter_servers, "worker": workers})
    server = tf.train.Server(cluster,job_name=FLAGS.job_name,task_index=FLAGS.task_index)

    if FLAGS.job_name == "ps":
        server.join()
    elif FLAGS.job_name == "worker":

        train_X = np.linspace(-1.0, 1.0, 100)
        train_Y = 2.0 * train_X + np.random.randn(*train_X.shape) * 0.33 + 10.0

        X = tf.placeholder("float")
        Y = tf.placeholder("float")

        # Assigns ops to the local worker by default.
        with tf.device(tf.train.replica_device_setter(
                worker_device="/job:worker/task:%d" % FLAGS.task_index,
                cluster=cluster)):

            w = tf.Variable(0.0, name="weight")
            b = tf.Variable(0.0, name="bias")
            # 損失函式，用於描述模型預測值與真實值的差距大小，常見為`均方差(Mean Squared Error)`
            loss = tf.square(Y - tf.multiply(X, w) - b)

            global_step = tf.Variable(0)

            train_op = tf.train.AdagradOptimizer(0.01).minimize(
                loss, global_step=global_step)

            saver = tf.train.Saver()
            summary_op = tf.summary.merge_all()
            init_op = tf.global_variables_initializer()

        # 建立 "Supervisor" 來負責監督訓練過程
        sv = tf.train.Supervisor(is_chief=(FLAGS.task_index == 0),
                                 logdir="/tmp/train_logs",
                                 init_op=init_op,
                                 summary_op=summary_op,
                                 saver=saver,
                                 global_step=global_step,
                                 save_model_secs=600)

        with sv.managed_session(server.target) as sess:
            loss_value = 100
            while not sv.should_stop() and loss_value > 70.0:
                # 執行一個非同步 training 步驟.
                # 若要執行同步可利用`tf.train.SyncReplicasOptimizer` 來進行
                for (x, y) in zip(train_X, train_Y):
                    _, step = sess.run([train_op, global_step],
                                       feed_dict={X: x, Y: y})

                loss_value = sess.run(loss, feed_dict={X: x, Y: y})
                print("步驟: {}, loss: {}".format(step, loss_value))

        sv.stop()


if __name__ == "__main__":
    tf.app.run()
```
> `tf.train.replica_device_setter(ps_tasks=0, ps_device='/job:ps', worker_device='/job:worker', merge_devices=True, cluster=None, ps_ops=None)` 指定方式。

撰寫完成後，透過以下指令來進行測試：
```shell=
$ python liner_dist.py --job_name=ps --task_index=0
$ python liner_dist.py --job_name=worker --task_index=0
$ python liner_dist.py --job_name=worker --task_index=1
```

## Tensorboard 視覺化工具
Tensorboard 是 TensorFlow 內建的視覺化工具，我們可以透過讀取事件紀錄結構化的資料，來顯示以下幾個項目來提供視覺化：

* **Event**：訓練過程中統計資料(平均值等)變化狀態.
* **Image**：訓練過程中紀錄的 Graph.
* **Audio**：訓練過程中紀錄的 Audio.
* **Histogram**：順練過程中紀錄的資料分散圖

一個範例程式如下所示：
```python
# coding=utf-8
import tensorflow as tf

logs_path = './tmp/1'

# 建立一個 graph，並建立兩個常數 op ，這些 op 稱為節點
g1 = tf.Graph()
with g1.as_default():
    a = tf.constant([1.5, 6.0], name='a')
    b = tf.Variable([1.5, 3.2], name='b')
    c = (a * b) + (a / b)
    d = c * a
    y = tf.assign(b, d)

# 在 session 執行 graph，並進行資料數據操作 `c`。
# 然後指派給 cpu 做運算
with tf.Session(graph=g1) as sess_cpu:
  with tf.device("/cpu:0"):
      sess_cpu.run(tf.global_variables_initializer())
      writer = tf.summary.FileWriter(logs_path, graph=g1)
      print(sess_cpu.run(y))

```

執行後會看到當前目錄產生`tmp_mnist` logs 檔案，這時候就可以透過 thensorboard 來視覺化訓練結果：
```shell=
$ tensorboard --logdir=run1:./tmp/1 --port=6006
```
> run1 是當有多次 log 被載入時做為區別用。
