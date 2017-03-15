---
title: Go 語言環境安裝
date: 2016-8-19 17:08:54
layout: default
categories:
- Golang
tags:
- Golang
- OS X
- Linux
---
Go 語言是 Google 開發的該世代 C 語言，延續 C 語言的一些優點，是一種靜態強刑別、編譯型，且具有並行機制與垃圾回收功能的語言。由於其`並行機制`讓 Go 在撰寫多執行緒與網路程式都非常容易。值得一提的是 Go 語言的設計者也包含過去設計 C 語言的 [Ken Thompson](https://en.wikipedia.org/wiki/Ken_Thompson)。目前 Go 語言基於 1.x 每半年發布一個版本。

<!--more-->

## Go 語言安裝
Go 語言安裝非常容易，目前已支援多個平台的作業系統，以下針對幾個常見的作業系統進行教學。

> P.S. 以下教學皆使用 64 bit 進行安裝。

### Linux
首先透過網路下載 Go 語言的壓縮檔：
```sh
$ wget https://storage.googleapis.com/golang/go1.8.linux-amd64.tar.gz
```

然後將壓縮檔內的資料全部解壓縮到`/usr/local`底下：
```sh
$ sudo tar -C /usr/local -xzf go1.8.linux-amd64.tar.gz
```

之後編輯`.bashrc`檔案，在最下面加入以下內容：
```
export GOROOT=/usr/local/go
export GOPATH=${HOME}/go
export PATH=$PATH:$GOPATH/bin:$GOROOT/bin
```

### Mac OS X
Mac OS X 安裝可以透過官方封裝好的檔案來進行安裝，下載 [go1.8.darwin-amd64.pkg](https://storage.googleapis.com/golang/go1.8.darwin-amd64.pkg)，然後雙擊進行安裝。

完成後，編輯`.bashrc`檔案來加入套件的安裝路徑：
```
export PATH=$PATH:/usr/local/go/bin
export GOPATH=~/Go
export PATH=$PATH:$GOPATH/bin
```

### 簡單入門
建立目錄`hello-go`，並新增檔案`hello.go`：
```sh
$ mkdir hello-go
$ cd hello-go && touch hello.go
```

接著編輯`hello.go`加入以下內容：
```go
package main
import "fmt"

func main() {
   fmt.Println("Hello world, GO !")
}
```

完成後執行以下指令：
```sh
$ go build
$ ./hello
Hello world, GO !
```

## 其他 Framework 與網站
以下整理相關 Go 語言的套件與不錯網站。

| 種類         	| 名稱                                                                                  |
|--------------|---------------------------------------------------------------------------------------|
| Web 框架     	| Beego、Martini、Gorilla、GoCraft、Net/HTTP、Revel、girl、XWeb、go-start、goku、web.go 	 |
| 系統處理框架 	 | apifs、goIRC                                                                          |
| 影音處理      | Gopher-Talkie、Videq                                                                  	|
| Social 框架   | ChannelMail.io                                                                        |


## 參考資訊
* [Gopher Gala 2015 Finalists](http://gophergala.com/blog/gopher/gala/2015/01/31/finalists/)
* [Web application frameworks](https://github.com/showcases/web-application-frameworks)
