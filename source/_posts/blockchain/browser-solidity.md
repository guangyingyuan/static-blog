---
title: 利用 Browser Solidity 部署智能合約
date: 2017-05-27 17:08:54
layout: page
categories:
- Blockchain
tags:
- Ethereum
- Blockchain
- Solidity
- Smart Contract
---
Browser Solidity 是一個 Web-based 的 Solidity 編譯器與 IDE。本節將說明如何安裝於 Linux 與 Docker 中。

這邊可以連結官方的 https://ethereum.github.io/browser-solidity 來使用; 該網站會是該專案的最新版本預覽。

<!--more-->

###  Ubuntu Server 手動安裝
首先安裝 Browser Solidity 要使用到的相關套件：
```sh
$ sudo apt-get install -y apache2 make g++ git
```

接著安裝 node.js 平台，來建置 App：
```sh
$ curl -sL https://deb.nodesource.com/setup_6.x | sudo -E bash -
$ sudo apt-get install nodejs
```

然後透過 git 將專案抓到 local 端，並進入目錄：
```sh
$ git clone https://github.com/ethereum/browser-solidity.git
$ cd browser-solidity
```

安裝相依套件與建置應用程式：
```sh
$ sudo npm install
$ sudo npm run build
```

完成後，將所以有目錄的資料夾與檔案搬移到 Apache HTTP Server 的網頁根目錄：
```sh
$ sudo cp ./* /var/www/html/
```
> 完成後就可以開啟網頁了。

### Docker 快速安裝
目前 Browser Solidity 有提供 [Docker Image](https://hub.docker.com/r/kairen/solidity/) 下載。這邊只需要透過以下指令就能夠建立 Browser Solidity Dashboard 環境：
```sh
$ docker run -d \
            -p 80:80 \
            --name solidity \
            kairen/solidity
```
