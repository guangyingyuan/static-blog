# KaiRen's Blog
Static blog source code for KaiRen.

## Quick Start
First, download [Node.js](https://nodejs.org/en/) and install Hexo in your computer:
```sh
$ npm install hexo-cli -g
```

Get source code from GitHub, and install packages afterwards:
```sh
$ git clone https://github.com/kairen/kr-static-blog.git
$ cd kr-static-blog
$ git submodule init && git submodule update
$ npm install
```

Now you can modify source to improve blog, and then type the following command to preview your changed:
```sh
$ hexo server

INFO  Start processing
INFO  Hexo is running at http://localhost:4000/. Press Ctrl+C to stop.
```
