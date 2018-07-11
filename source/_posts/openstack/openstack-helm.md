---
title: Deploy OpenStack on Kubernetes using OpenStack-helm
catalog: true
date: 2017-11-29 16:23:01
categories:
- OpenStack
tags:
- Openstack
- Kubernetes
- Helm
---
[OpenStack Helm](https://github.com/openstack/openstack-helm) 是一個提供部署建置的專案，其目的是為了推動 OpenStack 生產環境的解決方案，而這種部署方式採用容器化方式，並執行於 Kubernetes 系統上來提供 OpenStack 服務的管理與排程等使用。

![](https://i.imgur.com/8sMjowM.png)

<!--more-->

而本篇文章將說明如何建置多節點的 OpenStack Helm 環境來進行功能驗證。

## 節點與安裝版本
以下為各節點的硬體資訊。

| IP Address        |   Role           |   CPU    |   Memory   |
|-------------------|------------------|----------|------------|
| 172.22.132.10     | vip              |    -     |     -      |
| 172.22.132.101    | master1          |    4     |     16G    |
| 172.22.132.22     | node1            |    4     |     16G    |
| 172.22.132.24     | node2            |    4     |     16G    |
| 172.22.132.28     | node3            |    4     |     16G    |

使用 Kernel、作業系統與軟體版本：

|              	| 資訊描述                     |
|--------------	|----------------------------|
| 作業系統版本 	  | 16.04.3 LTS (Xenial Xerus) |
| Kernel 版本    | 4.4.0-101-generic          |
| Kubernetes   	| v1.8.4                     |
| Docker       	| Docker 17.09.0-ce          |
| Calico      	| v2.6.2                     |
| Etcd         	| v3.2.9                     |
| Ceph         	| v10.2.10                   |
| Helm         	| v2.7.0                     |

## Kubernetes 叢集
本節說明如何建立 Kubernetes Cluster，這邊採用 [kube-ansible](https://github.com/kairen/kube-ansible) 工具來建立。

### 初始化與設定基本需求
安裝前需要確認以下幾個項目：
* 所有節點的網路之間可以互相溝通。
* `部署節點`對其他節點不需要 SSH 密碼即可登入。
* 所有節點都擁有 Sudoer 權限，並且不需要輸入密碼。
* 所有節點需要安裝`Python`。
* 所有節點需要設定`/etc/host`解析到所有主機。
* `部署節點`需要安裝 **Ansible >= 2.4.0**。

```shell
# Ubuntu install
$ sudo apt-get install -y software-properties-common
$ sudo apt-add-repository -y ppa:ansible/ansible
$ sudo apt-get update && sudo apt-get install -y ansible git make

# CentOS install
$ sudo yum install -y epel-release
$ sudo yum -y install ansible cowsay
```

### 安裝與設定 Kube-ansible
首先取得最新穩定版本的 Kubernetes Ansible:
```shell
$ git clone https://github.com/kairen/kube-ansible.git
$ cd kube-ansible
```

然後新增`inventory`檔案來描述要部屬的主機角色:
```
[etcds]
172.22.132.101 ansible_user=ubuntu

[masters]
172.22.132.101 ansible_user=ubuntu

[nodes]
172.22.132.22 ansible_user=ubuntu
172.22.132.24 ansible_user=ubuntu
172.22.132.28 ansible_user=ubuntu

[kube-cluster:children]
masters
nodes

[kube-addon:children]
masters
```

接著編輯`group_vars/all.yml`檔案來添加與修改以下內容：
```yaml
# Kubenrtes version, only support 1.8.0+.
kube_version: 1.8.4

# CNI plugin
# Support: flannel, calico, canal, weave or router.
network: calico
pod_network_cidr: 10.244.0.0/16
# CNI opts: flannel(--iface=enp0s8), calico(interface=enp0s8), canal(enp0s8).
cni_iface: ""

# Kubernetes cluster network.
cluster_subnet: 10.96.0
kubernetes_service_ip: "{{ cluster_subnet }}.1"
service_ip_range: "{{ cluster_subnet }}.0/12"
service_node_port_range: 30000-32767
api_secure_port: 5443

# Highly Available configuration.
haproxy: true
keepalived: true # set `lb_vip_address` as keepalived vip, if this enable.
keepalived_vip_interface: "{{ ansible_default_ipv4.interface }}"

lb_vip_address: 172.22.132.10
lb_secure_port: 6443
lb_api_url: "https://{{ lb_vip_address }}:{{ lb_secure_port }}"

etcd_iface: ""

insecure_registrys:
- "172.22.132.253:5000" # 有需要的話

ceph_cluster: true
```
> * 這邊`insecure_registrys`為 deploy 節點的 Docker registry ip 與 port。
> * Extra addons 部分針對需求開啟，預設不會開啟。
> * 若想把 Etcd, VIP 與 Network plugin 綁定在指定網路的話，請修改`etcd_iface`, `keepalived_vip_interface` 與 `cni_iface`。其中`cni_iface`需要針對不同 Plugin 來改變。
> * 若想要修改部署版本的 Packages 的話，請編輯`roles/commons/packages/defaults/main.yml`來修改版本。

接著由於 OpenStack-helm 使用的 Kubernetes Controller Manager 不同，因此要修改`roles/commons/container-images/defaults/main.yml`的 Image 來源如下：
```yaml
...
  manager:
  name: kube-controller-manager
  repos: kairen/
  tag: "v{{ kube_version }}"
...
```

完後成修改 storage roles 設定版本並進行安裝。

首先編輯`roles/storage/ceph/defaults/main.yml`修改版本為以下：
```yaml
ceph_version: jewel
```

接著編輯`roles/storage/ceph/tasks/main.yml`修改成以下內容：
```yaml
---

- name: Install Ceph dependency packages
  include_tasks: install-ceph.yml

# - name: Create and copy generator config file
#   include_tasks: gen-config.yml
#   delegate_to: "{{ groups['masters'][0] }}"
#   run_once: true
#
# - name: Deploy Ceph components on Kubernetes
#   include_tasks: ceph-on-k8s.yml
#   delegate_to: "{{ groups['masters'][0] }}"
#   run_once: true

# - name: Label all storage nodes
#   shell: "kubectl label nodes node-type=storage"
#   delegate_to: "{{ groups['masters'][0] }}"
#   run_once: true
#   ignore_errors: true
```

### 部屬 Kubernetes 叢集
確認`group_vars/all.yml`與其他設定都完成後，就透過 ansible ping 來檢查叢集狀態：
```shell
$ ansible -i inventory all -m ping
...
172.22.132.101 | SUCCESS => {
    "changed": false,
    "failed": false,
    "ping": "pong"
}
...
```

接著就可以透過以下指令進行部署叢集：
```shell
$ ansible-playbook cluster.yml
...
TASK [cni : Apply calico network daemonset] *********************************************************************************************************************************
changed: [172.22.132.101 -> 172.22.132.101]

PLAY RECAP ******************************************************************************************************************************************************************
172.22.132.101             : ok=155  changed=58   unreachable=0    failed=0
172.22.132.22              : ok=117  changed=28   unreachable=0    failed=0
172.22.132.24              : ok=50   changed=18   unreachable=0    failed=0
172.22.132.28              : ok=51   changed=19   unreachable=0    failed=0
```

完成後，進入`master`節點執行以下指令確認叢集：
```shell
$ kubectl get node
NAME           STATUS    ROLES     AGE       VERSION
kube-master1   Ready     master    1h        v1.8.4
kube-node1     Ready     <none>    1h        v1.8.4
kube-node2     Ready     <none>    1h        v1.8.4
kube-node3     Ready     <none>    1h        v1.8.4

$ kubectl -n kube-system get po
NAME                                       READY     STATUS    RESTARTS   AGE
calico-node-js6qp                          2/2       Running   2          1h
calico-node-kx9xn                          2/2       Running   2          1h
calico-node-lxrjl                          2/2       Running   2          1h
calico-node-vwn5f                          2/2       Running   2          1h
calico-policy-controller-d549764f6-9kn9l   1/1       Running   1          1h
haproxy-kube-master1                       1/1       Running   1          1h
keepalived-kube-master1                    1/1       Running   1          1h
kube-apiserver-kube-master1                1/1       Running   1          1h
kube-controller-manager-kube-master1       1/1       Running   1          1h
kube-dns-7bd4879dc9-kxmx6                  3/3       Running   3          1h
kube-proxy-7tqkm                           1/1       Running   1          1h
kube-proxy-glzmm                           1/1       Running   1          1h
kube-proxy-krqxs                           1/1       Running   1          1h
kube-proxy-x9zdb                           1/1       Running   1          1h
kube-scheduler-kube-master1                1/1       Running   1          1h
```

檢查 kube-dns 是否連 host 都能夠解析:
```shell
$ nslookup kubernetes
Server:		10.96.0.10
Address:	10.96.0.10#53

Non-authoritative answer:
Name:	kubernetes.default.svc.cluster.local
Address: 10.96.0.1
```

接著安裝 Ceph 套件：
```sh
$ ansible-playbook storage.yml
```

## OpenStack-helm 叢集
本節說明如何建立 OpenStack on Kubernetes 使用 Helm，部署是使用 [openstack-helm](https://github.com/openstack/openstack-helm)。過程將透過 OpenStack-helm 來在 Kubernetes 建置 OpenStack 叢集。以下所有操作都在`kube-master1`上進行。

### Helm init
在開始前需要先將 Helm 進行初始化，以提供後續使用，然而這邊由於使用到 RBAC 的關係，因此需建立一個 Service account 來提供給 Helm 使用：
```shell
$ kubectl -n kube-system create sa tiller
$ kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller
$ helm init --service-account tiller
```
> 由於 `kube-ansible` 本身包含 Helm 工具, 因此不需要自己安裝，只需要依據上面指令進行 init 即可。

新增一個檔案`openrc`來提供環境變數：
```shell
export HELM_HOST=$(kubectl describe svc/tiller-deploy -n kube-system | awk '/Endpoints/{print $2}')
export OSD_CLUSTER_NETWORK=172.22.132.0/24
export OSD_PUBLIC_NETWORK=172.22.132.0/24
export WORK_DIR=local
export CEPH_RGW_KEYSTONE_ENABLED=true
```
> * `OSD_CLUSTER_NETWORK`與`OSD_PUBLIC_NETWORK`都是使用實體機器網路，這邊 daemonset 會使用 hostNetwork。
> * `CEPH_RGW_KEYSTONE_ENABLED` 在 Kubernetes 版本有點不穩，可依需求關閉。

完成後，透過 source 指令引入:
```shell
$ source openrc
$ helm version
Client: &version.Version{SemVer:"v2.7.0", GitCommit:"08c1144f5eb3e3b636d9775617287cc26e53dba4", GitTreeState:"clean"}
Server: &version.Version{SemVer:"v2.7.0", GitCommit:"08c1144f5eb3e3b636d9775617287cc26e53dba4", GitTreeState:"clean"}
```

### 事前準備
首先透過 Kubernetes label 來標示每個節點的角色：
```shell
kubectl label nodes openstack-control-plane=enabled --all
kubectl label nodes ceph-mon=enabled --all
kubectl label nodes ceph-osd=enabled --all
kubectl label nodes ceph-mds=enabled --all
kubectl label nodes ceph-rgw=enabled --all
kubectl label nodes ceph-mgr=enabled --all
kubectl label nodes openvswitch=enabled --all
kubectl label nodes openstack-compute-node=enabled --all
```
> 這邊為了避免過度的節點污染，因此不讓 masters 充當任何角色：
```shell
kubectl label nodes kube-master1 openstack-control-plane-
kubectl label nodes kube-master1 ceph-mon-
kubectl label nodes kube-master1 ceph-osd-
kubectl label nodes kube-master1 ceph-mds-
kubectl label nodes kube-master1 ceph-rgw-
kubectl label nodes kube-master1 ceph-mgr-
kubectl label nodes kube-master1 openvswitch-
kubectl label nodes kube-master1 openstack-compute-node-
```

由於使用 Kubernetes RBAC，而目前 openstack-helm 有 bug，不會正確建立 Service account 的 ClusterRoleBindings，因此要手動建立(這邊偷懶一下直接使用 Admin roles)：
```shell
$ cat <<EOF | kubectl create -f -
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: ceph-sa-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: system:serviceaccount:ceph:default
EOF

$ cat <<EOF | kubectl create -f -
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: openstack-sa-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: system:serviceaccount:openstack:default
EOF
```
> 若沒有建立的話，會有類似以下的錯誤資訊：
```
Error from server (Forbidden): error when creating "STDIN": secrets is forbidden: User "system:serviceaccount:ceph:default" cannot create secrets in the namespace "ceph"
```

下載最新版本 openstack-helm 專案：
```shell
$ git clone https://github.com/openstack/openstack-helm.git
$ cd openstack-helm
```

現在須建立 openstack-helm chart 來提供部署使用：
```shell
$ helm serve &
$ helm repo add local http://localhost:8879/charts
$ make
# output
...
1 chart(s) linted, no failures
if [ -d congress ]; then helm package congress; fi
Successfully packaged chart and saved it to: /root/openstack-helm/congress-0.1.0.tgz
make[1]: Leaving directory '/root/openstack-helm'
```

### Ceph Chart
在部署 OpenStack 前，需要先部署 Ceph 叢集，這邊透過以下指令建置：
```shell
$ helm install --namespace=ceph ${WORK_DIR}/ceph --name=ceph \
  --set endpoints.identity.namespace=openstack \
  --set endpoints.object_store.namespace=ceph \
  --set endpoints.ceph_mon.namespace=ceph \
  --set ceph.rgw_keystone_auth=${CEPH_RGW_KEYSTONE_ENABLED} \
  --set network.public=${OSD_PUBLIC_NETWORK} \
  --set network.cluster=${OSD_CLUSTER_NETWORK} \
  --set deployment.storage_secrets=true \
  --set deployment.ceph=true \
  --set deployment.rbd_provisioner=true \
  --set deployment.client_secrets=false \
  --set deployment.rgw_keystone_user_and_endpoints=false \
  --set bootstrap.enabled=true
```
> * `CEPH_RGW_KEYSTONE_ENABLED`是否啟動 Ceph RGW Keystone。
> * `OSD_PUBLIC_NETWORK`與`OSD_PUBLIC_NETWORK`為 Ceph 叢集網路。

成功安裝 Ceph chart 後，就可以透過 kubectl 來查看結果：
```shell
$ kubectl -n ceph get po
NAME                                   READY     STATUS    RESTARTS   AGE
ceph-mds-57798cc8f6-r898r              1/1       Running   2          10min
ceph-mon-96p9r                         1/1       Running   0          10min
ceph-mon-check-bd8875f87-whvhd         1/1       Running   0          10min
ceph-mon-qkj95                         1/1       Running   0          10min
ceph-mon-zx7tw                         1/1       Running   0          10min
ceph-osd-5fvfl                         1/1       Running   0          10min
ceph-osd-kvw9b                         1/1       Running   0          10min
ceph-osd-wcf5j                         1/1       Running   0          10min
ceph-rbd-provisioner-599ff9575-mdqnf   1/1       Running   0          10min
ceph-rbd-provisioner-599ff9575-vpcr6   1/1       Running   0          10min
ceph-rgw-7c8c5d4f6f-8fq9c              1/1       Running   3          10min
```

確認 Ceph 叢集建立正確：
```shell
$ MON_POD=$(kubectl get pods \
  --namespace=ceph \
  --selector="application=ceph" \
  --selector="component=mon" \
  --no-headers | awk '{ print $1; exit }')
$ kubectl exec -n ceph ${MON_POD} -- ceph -s

    cluster 02ad8724-dee0-4f55-829f-3cc24e2c7571
     health HEALTH_WARN
            too many PGs per OSD (856 > max 300)
     monmap e2: 3 mons at {kube-node1=172.22.132.22:6789/0,kube-node2=172.22.132.24:6789/0,kube-node3=172.22.132.28:6789/0}
            election epoch 8, quorum 0,1,2 kube-node1,kube-node2,kube-node3
      fsmap e5: 1/1/1 up {0=mds-ceph-mds-57798cc8f6-r898r=up:active}
     osdmap e21: 3 osds: 3 up, 3 in
            flags sortbitwise,require_jewel_osds
      pgmap v6053: 856 pgs, 10 pools, 3656 bytes data, 191 objects
            43091 MB used, 2133 GB / 2291 GB avail
                 856 active+clean
```
> Warn 這邊忽略，OSD 機器太少....。

接著為了讓 Ceph 可以在其他 Kubernetes namespace 中存取 PVC，這邊要產生 client secret key 於 openstack namespace 中來提供給 OpenStack 元件使用，這邊執行以下 Chart 來產生：
```shell
$ helm install --namespace=openstack ${WORK_DIR}/ceph --name=ceph-openstack-config \
  --set endpoints.identity.namespace=openstack \
  --set endpoints.object_store.namespace=ceph \
  --set endpoints.ceph_mon.namespace=ceph \
  --set ceph.rgw_keystone_auth=${CEPH_RGW_KEYSTONE_ENABLED} \
  --set network.public=${OSD_PUBLIC_NETWORK} \
  --set network.cluster=${OSD_CLUSTER_NETWORK} \
  --set deployment.storage_secrets=false \
  --set deployment.ceph=false \
  --set deployment.rbd_provisioner=false \
  --set deployment.client_secrets=true \
  --set deployment.rgw_keystone_user_and_endpoints=false
```

檢查 pod 與 secret 是否建立成功：
```shell
$ kubectl -n openstack get secret,po -a
NAME                          TYPE                                  DATA      AGE
secrets/default-token-q2r87   kubernetes.io/service-account-token   3         2m
secrets/pvc-ceph-client-key   kubernetes.io/rbd                     1         2m

NAME                                           READY     STATUS      RESTARTS   AGE
po/ceph-namespace-client-key-generator-w84n4   0/1       Completed   0          2m
```

### OpenStack Chart
確認沒問題後，就可以開始部署 OpenStack chart 了。首先先安裝 Mariadb cluster:
```shell
$ helm install --name=mariadb ./mariadb --namespace=openstack
```
> 這邊跑超久...34mins...，原因可能是 Storage 效能問題。

這邊正確執行後，會依序依據 StatefulSet 建立起 Pod 組成 Cluster：
```shell
$ kubectl -n openstack get po
NAME        READY     STATUS    RESTARTS   AGE
mariadb-0   1/1       Running   0          37m
mariadb-1   1/1       Running   0          4m
mariadb-2   1/1       Running   0          2m
```

當 Mariadb cluster 完成後，就可以部署一些需要的服務，如 RabbitMQ, OVS 等：
```shell
helm install --name=memcached ./memcached --namespace=openstack
helm install --name=etcd-rabbitmq ./etcd --namespace=openstack
helm install --name=rabbitmq ./rabbitmq --namespace=openstack
helm install --name=ingress ./ingress --namespace=openstack
helm install --name=libvirt ./libvirt --namespace=openstack
helm install --name=openvswitch ./openvswitch --namespace=openstack
```

上述指令若正確執行的話，會分別建立起以下服務：
```shell
$ kubectl -n openstack get po
NAME                                   READY     STATUS    RESTARTS   AGE
etcd-5c9bc8c97f-jpm2k                  1/1       Running   0          4m
ingress-api-jhjjv                      1/1       Running   0          4m
ingress-api-nx5qm                      1/1       Running   0          4m
ingress-api-vr8xf                      1/1       Running   0          4m
ingress-error-pages-86b9db69cc-mmq4p   1/1       Running   0          4m
libvirt-94xq5                          1/1       Running   0          4m
libvirt-lzfzs                          1/1       Running   0          4m
libvirt-vswxb                          1/1       Running   0          4m
mariadb-0                              1/1       Running   0          42m
mariadb-1                              1/1       Running   0          9m
mariadb-2                              1/1       Running   0          7m
memcached-746fcc894-cwhpr              1/1       Running   0          4m
openvswitch-db-7fjr2                   1/1       Running   0          4m
openvswitch-db-gtmcr                   1/1       Running   0          4m
openvswitch-db-hqmbt                   1/1       Running   0          4m
openvswitch-vswitchd-gptp9             1/1       Running   0          4m
openvswitch-vswitchd-s4cwd             1/1       Running   0          4m
openvswitch-vswitchd-tvxlg             1/1       Running   0          4m
rabbitmq-6fdb8879df-6vmz8              1/1       Running   0          4m
rabbitmq-6fdb8879df-875zz              1/1       Running   0          4m
rabbitmq-6fdb8879df-h5wj6              1/1       Running   0          4m
```

一旦所有基礎服務與元件都建立完成後，就可以開始部署 OpenStack 的專案 Chart，首先建立 Keystone 來提供身份認證服務：
```shell
$ helm install --namespace=openstack --name=keystone ./keystone \
  --set pod.replicas.api=1

$ kubectl -n openstack get po -l application=keystone
NAME                            READY     STATUS     RESTARTS   AGE
keystone-api-74c774d448-dkqmj   0/1       Init:0/1   0          4m
keystone-bootstrap-xpdtl        0/1       Init:0/1   0          4m
keystone-db-sync-2bxtp          1/1       Running    0          4m        0          29s
```
> 這邊由於叢集規模問題，副本數都為一份。

這時候會先建立 Keystone database tables，完成後將啟動 API pod，如以下結果：
```shell
$ kubectl -n openstack get po -l application=keystone
NAME                            READY     STATUS    RESTARTS   AGE
keystone-api-74c774d448-dkqmj   1/1       Running   0          11m
```

如果安裝支援 RGW 的 Keystone endpoint 的話，可以使用以下方式建立：
```shell
$ helm install --namespace=openstack ${WORK_DIR}/ceph --name=radosgw-openstack \
  --set endpoints.identity.namespace=openstack \
  --set endpoints.object_store.namespace=ceph \
  --set endpoints.ceph_mon.namespace=ceph \
  --set ceph.rgw_keystone_auth=${CEPH_RGW_KEYSTONE_ENABLED} \
  --set network.public=${OSD_PUBLIC_NETWORK} \
  --set network.cluster=${OSD_CLUSTER_NETWORK} \
  --set deployment.storage_secrets=false \
  --set deployment.ceph=false \
  --set deployment.rbd_provisioner=false \
  --set deployment.client_secrets=false \
  --set deployment.rgw_keystone_user_and_endpoints=true

$ kubectl -n openstack get po -a -l application=ceph
NAME                                        READY     STATUS      RESTARTS   AGE
ceph-ks-endpoints-vfg4l                     0/3       Completed   0          1m
ceph-ks-service-tr9xt                       0/1       Completed   0          1m
ceph-ks-user-z5tlt                          0/1       Completed   0          1m
```

完成後，安裝 Horizon chart 來提供 OpenStack dashbaord：
```shell
$ helm install --namespace=openstack --name=horizon ./horizon \
  --set network.enable_node_port=true \
  --set network.node_port=31000

$ kubectl -n openstack get po -l application=horizon
NAME                       READY     STATUS    RESTARTS   AGE
horizon-7c54878549-45668   1/1       Running   0          3m
```

接著安裝 Glance chart 來提供 OpenStack image service。目前 Glance 支援幾個 backend storage:
* **pvc**: 一個簡單的 Kubernetes PVCs 檔案後端。
* **rbd**: 使用 Ceph RBD 來儲存 images。
* **radosgw**: 使用 Ceph RGW 來儲存 images。
* **swift**: 另用 OpenStack switf 所提供的物件儲存服務來儲存 images.

這邊可以利用以下方式來部署不同的儲存後端：
```shell
$ export GLANCE_BACKEND=radosgw
$ helm install --namespace=openstack --name=glance ./glance \
  --set pod.replicas.api=1 \
  --set pod.replicas.registry=1 \
  --set storage=${GLANCE_BACKEND}

$ kubectl -n openstack get po -l application=glance
NAME                               READY     STATUS    RESTARTS   AGE
glance-api-6cd8b856d6-lhzfs        1/1       Running   0          14m
glance-registry-599f8b857b-gt4c6   1/1       Running   0          14m
```

接著安裝 Neutron chart 來提供 OpenStack 虛擬化網路服務：
```shell
$ helm install --namespace=openstack --name=neutron ./neutron \
  --set pod.replicas.server=1

$ kubectl -n openstack get po -l application=neutron
NAME                              READY     STATUS    RESTARTS   AGE
neutron-dhcp-agent-2z49d          1/1       Running   0          9h
neutron-dhcp-agent-d2kn8          1/1       Running   0          9h
neutron-dhcp-agent-mrstl          1/1       Running   0          9h
neutron-l3-agent-9f9mw            1/1       Running   0          9h
neutron-l3-agent-cshzw            1/1       Running   0          9h
neutron-l3-agent-j5vb9            1/1       Running   0          9h
neutron-metadata-agent-6bfb2      1/1       Running   0          9h
neutron-metadata-agent-kxk9c      1/1       Running   0          9h
neutron-metadata-agent-w8cnl      1/1       Running   0          9h
neutron-ovs-agent-j2549           1/1       Running   0          9h
neutron-ovs-agent-plj9t           1/1       Running   0          9h
neutron-ovs-agent-xlx7z           1/1       Running   0          9h
neutron-server-6f45d74b87-6wmck   1/1       Running   0          9h
```

接著安裝 Nova chart 來提供 OpenStack 虛擬機運算服務:
```shell
$ helm install --namespace=openstack --name=nova ./nova \
  --set pod.replicas.api_metadata=1 \
  --set pod.replicas.osapi=1 \
  --set pod.replicas.conductor=1 \
  --set pod.replicas.consoleauth=1 \
  --set pod.replicas.scheduler=1 \
  --set pod.replicas.novncproxy=1

$ kubectl -n openstack get po -l application=nova
NAME                                 READY     STATUS    RESTARTS   AGE
nova-api-metadata-84fdc84fd7-ldzrh   1/1       Running   1          9h
nova-api-osapi-57f599c6d6-pqrjv      1/1       Running   0          9h
nova-compute-8rvm9                   2/2       Running   0          9h
nova-compute-cbk7h                   2/2       Running   0          9h
nova-compute-tf2jb                   2/2       Running   0          9h
nova-conductor-7f5bc76d79-bxwnb      1/1       Running   0          9h
nova-consoleauth-6946b5884f-nss6n    1/1       Running   0          9h
nova-novncproxy-d789dccff-7ft9q      1/1       Running   0          9h
nova-placement-api-f7c79578f-hj2g9   1/1       Running   0          9h
nova-scheduler-778866f555-mmksg      1/1       Running   0          9h
```

接著安裝 Cinfer chart 來提供 OpenStack 區塊儲存服務:
```shell
$ helm install --namespace=openstack --name=cinder ./cinder \
  --set pod.replicas.api=1

$ kubectl -n openstack get po -l application=cinder
NAME                                READY     STATUS    RESTARTS   AGE
cinder-api-5cc89f5467-ssm8k         1/1       Running   0          32m
cinder-backup-67c4d8dfdb-zfsq4      1/1       Running   0          32m
cinder-scheduler-65f9dd49bf-6htwg   1/1       Running   0          32m
cinder-volume-69bfb67b4-bmst2       1/1       Running   0          32m
```

(option)都完成後，將 Horizon 服務透過 NodePort 方式曝露出來(如果上面 Horizon chart 沒反應的話)，執行以下指令編輯：
```shell
$ kubectl -n openstack edit svc horizon-int
# 修改 type:
  type: NodePort
```

最後連接 [Horizon Dashboard](http://172.22.132.10:31000)，預設使用者為`admin/password`。

![](https://i.imgur.com/8yunUPy.png)

其他 Chart 可以利用以下方式來安裝，如 Heat chart：
```shell
$ helm install --namespace=openstack --name=heat ./heat

$ kubectl -n openstack get po -l application=heat
NAME                              READY     STATUS    RESTARTS   AGE
heat-api-5cf45d9d44-qrt69         1/1       Running   0          13m
heat-cfn-79dbf55789-bq4wh         1/1       Running   0          13m
heat-cloudwatch-bcc4647f4-4c4ln   1/1       Running   0          13m
heat-engine-55cfcc86f8-cct4m      1/1       Running   0          13m
```

## 測試 OpenStack 功能
在`kube-master1`安裝 openstack client:
```shell
$ sudo pip install python-openstackclient
```

建立`adminrc`來提供 client 環境變數：
```shell
export OS_PROJECT_DOMAIN_NAME=default
export OS_USER_DOMAIN_NAME=default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=password
export OS_AUTH_URL=http://keystone.openstack.svc.cluster.local:80/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
```

引入環境變數，並透過 openstack client 測試：
```shell
$ source adminrc
$ openstack user list
+----------------------------------+-----------+
| ID                               | Name      |
+----------------------------------+-----------+
| 42f0d2e7823e413cb469f9cce731398a | glance    |
| 556a2744811f450098f64b37d34192d4 | nova      |
| a97ec73724aa4445b2d575be54f23240 | cinder    |
| b28a5dcfd18948419e14acba7ecf6f63 | swift     |
| d1f312b6bb7c460eb7d8d78c8bf350fc | admin     |
| dc326aace22c4314a0100865fe4f57c2 | neutron   |
| ec5d6d3c529847b29a1c9187599c8a6b | placement |
+----------------------------------+-----------+
```

接著需要設定對外網路來提供給 VM 存取，在有`neutron-l3-agent`節點上，新增一個腳本`setup-gateway.sh`：
```shell
#!/bin/bash
set -x

# Assign IP address to br-ex
OSH_BR_EX_ADDR="172.24.4.1/24"
OSH_EXT_SUBNET="172.24.4.0/24"
sudo ip addr add ${OSH_BR_EX_ADDR} dev br-ex
sudo ip link set br-ex up

# Setup masquerading on default route dev to public subnet
DEFAULT_ROUTE_DEV="enp3s0"
sudo iptables -t nat -A POSTROUTING -o ${DEFAULT_ROUTE_DEV} -s ${OSH_EXT_SUBNET} -j MASQUERADE
```
> * 網卡記得修改`DEFAULT_ROUTE_DEV`。
> * 這邊因為沒有額外提供其他張網卡，所以先用 bridge 處理。

然後透過執行該腳本建立一個 bridge 網路：
```shell
$ chmod u+x setup-gateway.sh
$ ./setup-gateway.sh
```

確認完成後，接著建立 Neutron ext net，透過以下指令進行建立：
```shell
$ openstack network create \
   --share --external \
   --provider-physical-network external \
   --provider-network-type flat ext-net

$ openstack subnet create --network ext-net \
    --allocation-pool start=172.24.4.10,end=172.24.4.100 \
    --dns-nameserver 8.8.8.8 --gateway 172.24.4.1 \
    --subnet-range 172.24.4.0/24 \
    --no-dhcp ext-subnet

$ openstack router create router1
$ neutron router-gateway-set router1 ext-net
```

直接進入 Dashboard 新增 Self-service Network:
![](https://i.imgur.com/lqMrgqs.png)

加入到 router1:
![](https://i.imgur.com/4aNnF3O.png)

完成後，就可以建立 instance，這邊都透過 Dashboard 來操作：
![](https://i.imgur.com/fCYkxSC.png)

透過 SSH 進入 instance：
![](https://i.imgur.com/Ijylo9X.png)

## Refers
* [sydney-workshop](https://github.com/portdirect/sydney-workshop)
* [Multi Node](https://docs.openstack.org/openstack-helm/latest/install/multinode.html)
