---
title: 以 Keystone 作為 Kubernetes 使用者認證
date: 2018-5-30 17:08:54
catalog: true
categories:
- Kubernetes
tags:
- Kubernetes
- Keystone
---
本文章將說明如何整合 Keystone 來提供給 Kubernetes 進行使用者認證。但由於 Keystone 整合 Kubernetes 認證在 1.10.x 版本已從原生移除(`--experimental-keystone-url`, `--experimental-keystone-ca-file`)，並轉而使用 [cloud-provider-openstack](https://github.com/kubernetes/cloud-provider-openstack) 中的 Webhook 來達成，而篇將說明如何建置與設定以整合該 Webhook。

<!--more-->

## 節點資訊
本教學將以下列節點數與規格來進行部署 Kubernetes 叢集，作業系統以`Ubuntu 16.x`進行測試：

| IP Address  | Hostname   | CPU | Memory |
|-------------|------------|-----|--------|
|172.22.132.20| k8s        | 4   | 8G     |
|172.22.132.21| keystone   | 4   | 8G     |

> * `k8s`為 all-in-one Kubernetes 節點(就只是個執行 kubeadm init 的節點)。
> * `keystone`利用 DevStack 部署一台 all-in-one OpenStack。

## 事前準備
開始安裝前需要確保以下條件已達成：

* `k8s`節點以 kubeadm 部署成 Kubernetes v1.9+ all-in-one 環境。請參考 [用 kubeadm 部署 Kubernetes 叢集](https://kairen.github.io/2016/09/29/kubernetes/deploy/kubeadm/)。

* 在`k8s`節點安裝 openstack-client：

```sh
$ sudo apt-get update && sudo  apt-get install -y python-pip
$ export LC_ALL=C; sudo pip install python-openstackclient
```

* `keystone`節點部署成 OpenStack all-in-one 環境。請參考 [DevStack](https://docs.openstack.org/devstack/latest/)。

## Kubernetes 與 Keystone 整合
本節將逐節說明如何設定以整合 Keystone。

### 建立 Keystone User 與 Roles
當`keystone`節點的 OpenStack 部署完成後，進入到節點建立測試用 User 與 Roles：
```sh
$ sudo su - stack
$ cd devstack
$ source openrc admin admin

# 建立 Roles
$ for role in "k8s-admin" "k8s-viewer" "k8s-editor"; do
    openstack role create $role;
  done

# 建立 User
$ openstack user create demo_editor --project demo --password secret
$ openstack user create demo_admin --project demo --password secret

# 加入 User 至 Roles
$ openstack role add --user demo --project demo k8s-viewer
$ openstack role add --user demo_editor --project demo k8s-editor
$ openstack role add --user demo_admin --project demo k8s-admin
```

### 在 Kubernetes 安裝 Keystone Webhook
進入`k8s`節點，首先導入下載的檔案來源：
```sh
$ export URL="https://kairen.github.io/files/openstack/keystone"
```

新增一些腳本，來提供導入不同使用者環境變數給 OpenStack Client 使用：
```sh
$ export KEYSTONE_HOST="172.22.132.21"
$ export USER_PASSWORD="secret"
$ for n in "admin" "demo" "demoadmin" "demoeditor" "altdemo"; do
    wget ${URL}/openrc-${n} -O ~/openrc-${n}
    sed -i "s/KEYSTONE_HOST/${KEYSTONE_HOST}/g" ~/openrc-${n}
    sed -i "s/USER_PASSWORD/${USER_PASSWORD}/g" ~/openrc-${n}
  done
```

下載 Keystone Webhook Policy 檔案，然後執行指令修改內容：
```sh
$ sudo wget ${URL}/webhook-policy.json -O /etc/kubernetes/webhook-policy.json
$ source ~/openrc-demo
$ PROJECT_ID=$(openstack project list | awk '/demo/ {print$2}')
$ sudo sed -i "s/PROJECT_ID/${PROJECT_ID}/g" /etc/kubernetes/webhook-policy.json
```

然後下載與部署 Keystone Webhook YAML 檔：
```sh
$ wget ${URL}/keystone-webhook-ds.conf -O keystone-webhook-ds.yml
$ KEYSTONE_HOST="172.22.132.21"
$ sed -i "s/KEYSTONE_HOST/${KEYSTONE_HOST}/g" keystone-webhook-ds.yml
$ kubectl create -f keystone-webhook-ds.yml
configmap "keystone-webhook-kubeconfig" created
daemonset.apps "keystone-auth-webhook" created
```

透過 kubectl 確認 Keystone Webhook 是否部署成功：
```sh
$ kubectl -n kube-system get po -l component=k8s-keystone
NAME                          READY     STATUS    RESTARTS   AGE
keystone-auth-webhook-5qqwn   1/1       Running   0          1m
```

透過 cURL 確認是否能夠正確存取：
```sh
$ source ~/openrc-demo
$ TOKEN=$(openstack token issue -f yaml -c id | awk '{print $2}')
$ cat << EOF | curl -kvs -XPOST -d @- https://localhost:8443/webhook | python -mjson.tool
{
  "apiVersion": "authentication.k8s.io/v1beta1",
  "kind": "TokenReview",
  "metadata": {
    "creationTimestamp": null
  },
  "spec": {
    "token": "$TOKEN"
  }
}
EOF

# output
{
    "apiVersion": "authentication.k8s.io/v1beta1",
    "kind": "TokenReview",
    "metadata": {
        "creationTimestamp": null
    },
    "spec": {
        "token": "gAAAAABbFi1SacEPNstSuSuiBXiBG0Y_DikfbiR75j3P-CJ8CeaSKXa5kDQvun4LZUq8U6ehuW_RrQwi-N7j8t086uN6a4hLnPPGmvc6K_Iw0BZHZps7G1R5WniHZ8-WTUxtkMJROSz9eG7m33Bp18mvgx-P179QiwNYxLivf_rjnxePmvujNow"
    },
    "status": {
        "authenticated": true,
        "user": {
            "extra": {
                "alpha.kubernetes.io/identity/project/id": [
                    "3ebcb1da142d427db04b8df43f6cb76a"
                ],
                "alpha.kubernetes.io/identity/project/name": [
                    "demo"
                ],
                "alpha.kubernetes.io/identity/roles": [
                    "k8s-viewer",
                    "Member",
                    "anotherrole"
                ]
            },
            "groups": [
                "3ebcb1da142d427db04b8df43f6cb76a"
            ],
            "uid": "19748c0131504b87a4117e49c67383c6",
            "username": "demo"
        }
    }
}
```

### 設定 kube-apiserver 使用 Webhook
進入`k8s`節點，然後修改`/etc/kubernetes/manifests/kube-apiserver.yaml`檔案，加入以下內容：
```yml
...
spec:
  containers:
  - command:
    ...
    # authorization-mode 加入 Webhook
    - --authorization-mode=Node,RBAC,Webhook
    - --runtime-config=authentication.k8s.io/v1beta1=true
    - --authentication-token-webhook-config-file=/srv/kubernetes/webhook-auth
    - --authorization-webhook-config-file=/srv/kubernetes/webhook-auth
    - --authentication-token-webhook-cache-ttl=5m
    volumeMounts:
    ...
    - mountPath: /srv/kubernetes/webhook-auth
      name: webhook-auth-file
      readOnly: true
  volumes:
  ...
  - hostPath:
      path: /srv/kubernetes/webhook-auth
      type: File
    name: webhook-auth-file
```

完成後重新啟動 kubelet(或者等待 static pod 自己更新)：
```sh
$ sudo systemctl restart kubelet
```

## 驗證部署結果
進入`k8s`節點，然後設定 kubectl context 並使用 openstack provider：
```sh
$ kubectl config set-credentials openstack --auth-provider=openstack
$ kubectl config \
    set-context --cluster=kubernetes \
    --user=openstack \
    openstack@kubernetes \
    --namespace=default

$ kubectl config use-context openstack@kubernetes
```

測試 demo 使用者的存取權限是否有被限制：
```sh
$ source ~/openrc-demo
$ kubectl get pods
No resources found.

$ cat <<EOF | kubectl create -f -
apiVersion: v1
kind: Pod
metadata:
  name: nginx-pod
spec:
  restartPolicy: Never
  containers:
  - image: nginx
    name: nginx-app
EOF
# output
Error from server (Forbidden): error when creating "STDIN": pods is forbidden: User "demo" cannot create pods in the namespace "default"
```
> 由於 demo 只擁有 k8s-viewer role，因此只能進行 get, list 與 watch API。

測試 demo_editor 使用者是否能夠建立 Pod：
```sh
$ source ~/openrc-demoeditor
$ cat <<EOF | kubectl create -f -
apiVersion: v1
kind: Pod
metadata:
  name: nginx-pod
spec:
  restartPolicy: Never
  containers:
  - image: nginx
    name: nginx-app
EOF
# output
pod "nginx-pod" created
```
> 這邊可以看到 demo_editor 因為擁有 k8s-editor role，因此能夠執行 create API。

測試 alt_demo 是否被禁止存取任何 API：
```sh
$ source ~/openrc-altdemo
$ kubectl get po
Error from server (Forbidden): pods is forbidden: User "alt_demo" cannot list pods in the namespace "default"
```
> 由於 alt_demo 不具備任何 roles，因此無法存取任何 API。
