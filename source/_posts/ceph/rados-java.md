---
layout: default
title: 利用 Rados-java 存取 Ceph
date: 2016-5-15 17:08:54
categories:
- Ceph
tags:
- Ceph
- Storage
- Java
---
[rados-java](https://github.com/ceph/rados-java) 透過 JNA 來綁定 librados (C) 的 API 來提供給 Java 使用，並且實作了 RADOS 與 RBD 的 API，由於透過 JNA 的關析，故不用建構任何的 Header 檔案(.h)。因此我們可以在擁有 JNA 與 librados 的系統上使用本函式庫。

<!--more--->

## 環境準備
在開始進行之前，需要滿足以下幾項要求：
* 需要部署一個 Ceph 叢集，可以參考[Ceph Docker 部署](https://kairen.github.io/2016/03/15/ceph/ceph-docker/)。
* 執行 rados-java 程式的環境，要能夠與 Ceph 叢集溝通(ceph.conf、admin key)。
* 需要安裝 Ceph 相關 library。可以透過以下方式安裝：
> ```sh
$ wget -q -O- 'https://download.ceph.com/keys/release.asc' | sudo apt-key add -
$ echo "deb https://download.ceph.com/debian-kraken/ $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/ceph.list
$ sudo apt-get update && sudo apt-get install -y ceph
```

## 建構 rados-java jar 檔
首先需要安裝一些相關軟體來提供建構 rados-java 使用：
```sh
$ sudo apt-get install -y software-properties-common
$ sudo add-apt-repository -y ppa:webupd8team/java
$ sudo apt-get update
$ sudo apt-get -y install oracle-java8-installer git libjna-java
```

接著安裝 maven 3.3.1 + 工具：
```sh
$ wget "http://ftp.tc.edu.tw/pub/Apache/maven/maven-3/3.3.9/binaries/apache-maven-3.3.9-bin.tar.gz"
$ tar -zxf apache-maven-3.3.9-bin.tar.gz
$ sudo cp -R apache-maven-3.3.9 /usr/local/
$ sudo ln -s /usr/local/apache-maven-3.3.9/bin/mvn /usr/bin/mvn
$ mvn --version
```

然後透過 Git 取得 rados-java 原始碼：
```sh
$ git clone "https://github.com/ceph/rados-java.git"
$ cd rados-java && git checkout v0.1.3
$ mvn
```

完成後將 Jar 檔複製到`/usr/share/java/`底下，並設定 JAR 連結 JVM Class path：
```sh
$ sudo cp target/rados-0.1.3.jar /usr/share/java/
$ sudo ln -s /usr/share/java/rados-0.1.3.jar /usr/lib/jvm/java-8-oracle/jre/lib/ext/
$ sudo ln -s /usr/share/java/jna-4.2.2.jar /usr/lib/jvm/java-8-oracle/jre/lib/ext/
```
> 這邊也可以直接透過下載 Jar 檔來完成：
```sh
$ wget "https://download.ceph.com/maven/com/ceph/rados/0.1.3/rados-0.1.3.jar"
$ sudo cp rados-0.1.3.jar /usr/share/java/
```

最後就可以透過簡單範例程式存取 Ceph 了。

## 簡單測試程式
這邊透過 Java 程式連結到 Ceph 叢集，並且存取`data`儲存池來寫入物件，建立與編輯`Example.java`檔，加入以下程式內容：
```java
import com.ceph.rados.Rados;
import com.ceph.rados.RadosException;

import java.io.File;
import com.ceph.rados.IoCTX;

public class Example {
    public static void main (String args[]){
      try {
          Rados cluster = new Rados("admin");
          File f = new File("/etc/ceph/ceph.conf");
          cluster.confReadFile(f);

          cluster.connect();
          System.out.println("Connected to the cluster.");

          IoCTX io = cluster.ioCtxCreate("data"); /* Pool Name */
          String oidone = "kyle-say";
          String contentone = "Hello World!";
          io.write(oidone, contentone);

          String oidtwo = "my-object";
          String contenttwo = "This is my object.";
          io.write(oidtwo, contenttwo);

          String[] objects = io.listObjects();
          for (String object: objects)
              System.out.println("Put " + object);

          /* io.remove(oidone);
             io.remove(oidtwo); */

          cluster.ioCtxDestroy(io);

        } catch (RadosException e) {
          System.out.println(e.getMessage() + ": " + e.getReturnValue());
        }
    }
}
```

撰寫完程式後，執行以下指令來看結果：
```sh
$ javac Example.java
$ sudo java Example
Connected to the cluster.
Put kyle-say
Put my-object
```

## 透過 rados 指令檢查
當程式正確執行後，就可以透過 rados 指令來確認物件是否正確被寫入：
```sh
$ sudo rados -p data ls
kyle-say
my-object
```

透過 Get 指令來取得物件的內容：
```sh
$ sudo rados -p data get kyle-say -
Hello World!

$ sudo rados -p data get my-object -
This is my object.
```
