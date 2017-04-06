---
title: SaltStack 介紹
layout: default
comments: true
date: 2016-02-15 12:23:01
categories:
- DevOps
tags:
- DevOps
- Automation Engine
---
Saltstack 是一套基礎設施管理開發套件、簡單易部署、可擴展到管理成千上萬的伺服器、控制速度佳(以 ms 為單位)。Saltstack 提供了動態基礎設施溝通總線用於編配、遠端執行、配置管理等等。Saltstack 是從 2011 年開始的專案，已經是很成熟的開源專案。該專案簡單的兩大基礎功能就是配置管理與遠端指令執行。

Saltstack 採用集中化管理，我們一般可以理解為 Puppet 的簡化版本與 [Func](https://fedorahosted.org/func/)
的加強版本。Saltstack 是基於 Python 語言開發的，結合輕量級訊息佇列（ZeroMQ）以及 Python 第三方模組（Pyzmq、PyCrypto、Pyjinja2、python-msgpack與PyYAML等）。

![](/images/devops/saltstack-arch.png)

<!--more-->

**優點**：
* 部署簡單與方便。
* 支持大部分 UNIX/Liunx 及 Windows 環境。
* 主從集中化管理。
* 配置簡單、功能強大與擴展性強。
* 主控端（Master）與被控制端（Minion）基於憑證認證。
* 支援 API 以及自定義模組，透過 Python 輕鬆擴展。
* 社群活躍。

**缺點**：
* Web UI 雖然有，但是沒有報表功能。
* 需要 Agent

透過 Saltstack 環境，我們可在成千上萬的伺服器進行批次的指令執行，根據不同的集中化管理配置、分散檔案、收集伺服器資料、作業系統基礎環境以及軟體套件等。

# 參考資源
* [SaltStack介紹和架構解析](http://openskill.cn/article/183?utm_source=tuicool&utm_medium=referral)
