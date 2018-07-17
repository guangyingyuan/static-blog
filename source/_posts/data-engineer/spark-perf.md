---
title: Databricks spark-perf Benchmark
date: 2016-07-17 17:08:54
catalog: true
categories:
- Spark
tags:
- Spark
- Benchmark
- Mesos
---
本範例為利用 [spark-perf](https://github.com/databricks/spark-perf) 針對SparkStreaming進行效能測試

系統需求:
* Ubuntu 14.04
* Hadoop2.6.0
* Spark1.5.2 + Mesos 安裝

## 設定 Spark-perf
首先透過 Git 下載 Sparo-perf 專案：
```sh
$ git clone https://github.com/databricks/spark-perf
```

完成後，進入`spark-perf/config`目錄，並透過以下指令修改組態檔：
```sh
$ cd spark-perf/config
$ cp config.py.template config.py
```

這邊修改`config.py`檔案以下內容：

* 設定 Spark 根目錄`SPARK_HOME_DIR = /opt/spark`。
  * Mesos 模式：`SPARK_CLUSTER_URL = mesos://10.26.1.101:5050`。
  * YARN 模式：`SPARK_CLUSTER_URL = yarn-cluster`。
* 設定 Java memory：`JavaOptionSet("spark.executor.memory", ["2g"])`。
* 設定 Spark Driver memory：`SPARK_DRIVER_MEMORY = "512m"`。
* 設定 SparkStreaming 中的 Spark executor memory：`JavaOptionSet("spark.executor.memory", ["512m"])`。


設定 Spark 測試項目，因本範例為 Streaming 效能評估，故將`STREAMING_TESTS`設定`True`，其餘設定`False`
> spark-perf 能針對 SparkSQL、SparkMlib、SparkCoreRDD 以及 SparkStreaming 等項目做效能評估。

```sh
RUN_SPARK_TESTS = False
RUN_PYSPARK_TESTS = False
RUN_STREAMING_TESTS = True
RUN_MLLIB_TESTS = False
RUN_PYTHON_MLLIB_TESTS = False

PREP_SPARK_TESTS = False
PREP_PYSPARK_TESTS = False
PREP_STREAMING_TESTS = True
PREP_MLLIB_TESTS = False
```

設定`batch-duration`批次時間設定：

* 項目`state-by-key`、`group-by-key-and-window`、`reduce-by-key-and-window` 的批次時間設定。
  * `STREAMING_KEY_VAL_TEST_OPTS`中的`streaming_batch_duration_opts(1000)`。
* `hdfs-recovery` 的批次時間設定。
  * `STREAMING_HDFS_RECOVERY_TEST_OPTS`中的`streaming_batch_duration_opts(5000)`。

設定`total-duration`效能測試時間設定：
```sh
STREAMING_COMMON_OPTS = [
    OptionSet("total-duration", [300]),
    OptionSet("hdfs-url", [HDFS_URL]),
]
```

設定 SparkStreaming 測試項目，於`config.py`檔案中的搜尋`STREAMING_TESTS`來查看。測試項目可分為 5 個項目，如下：

* `basic`，測試 setup 是否正確。
* `state-by-key`，狀態紀錄的計數評估。
* `group-by-key-and-window`，groupByKey 的評估。
* `reduce-by-key-and-window`，reduceByKey 的評估。
* `hdfs-recovery`，checkpoint 備份恢復效能評估。


## 開始測試

首先執行測試指令：
```sh
$ cd spark-perf/bin
$ ./run --config ../config/config.py
```

評估`state-by-key`結果如下：
```sh
Result: count: 30, avg: 0.846 s, stdev: 0.244 s, min: 0.630 s,
25%: 0.707 s, 50%: 0.738 s, 75%: 0.824 s, max: 1.394 s
```

評估結果也可於`bin/results`中查看：
```sh
$ ubuntu@spark-master:/opt/spark-perf/bin/results$ ls
streaming_perf_output__2016-03-12_07-19-19
streaming_perf_output__2016-03-12_07-19-19_logs
```
