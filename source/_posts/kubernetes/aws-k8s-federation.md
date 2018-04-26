---
title: 在 AWS 上建立跨地區的 Kubernetes Federation 叢集
date: 2018-4-21 17:08:54
layout: page
categories:
- Kubernetes
tags:
- Kubernetes
- AWS
- Kops
- Federation
---
本篇延續先前 On-premises Federation 與 Kops 經驗來嘗試在 AWS 上建立 Federaion 叢集，這邊架構如下圖所示：

![](/images/kops-fed/fed-clusters.png)

<!--more-->

本次安裝的軟體版本：
* Kubernetes v1.9.3
* kops v1.9.0
* kubefed v1.10

## 節點資訊
測試環境為 AWS EC2 虛擬機器，共有三組叢集：

US West(Oregon) 叢集，也是 Federation 控制平面叢集：

| Host       | vCPU | RAM |
|------------|------|-----|
| us-west-m1 | 1    | 2G  |
| us-west-n1 | 1    | 2G  |
| us-west-n2 | 1    | 2G  |

US East(Ohio) 叢集:

| Host       | vCPU | RAM |
|------------|------|-----|
| us-east-m1 | 1    | 2G  |
| us-east-n1 | 1    | 2G  |
| us-east-n2 | 1    | 2G  |

Asia Pacific(Tokyo) 叢集:

| Host            | vCPU | RAM |
|-----------------|------|-----|
| ap-northeast-m1 | 1    | 2G  |
| ap-northeast-n1 | 1    | 2G  |
| ap-northeast-n2 | 1    | 2G  |

## 事前準備
開始前，需要先安裝下列工具到操作機器上來提供使用：
* [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)：用來操作部署完成的 Kubernetes 叢集。
* [kops](https://github.com/kubernetes/kops)：用來部署與管理公有雲上的 Kubernetes 叢集。

Mac OS X：
```sh
$ brew update && brew install kops
```

Linux distro：
```sh
$ curl -LO https://github.com/kubernetes/kops/releases/download/$(curl -s https://api.github.com/repos/kubernetes/kops/releases/latest | grep tag_name | cut -d '"' -f 4)/kops-linux-amd64
$ chmod +x kops-linux-amd64 && sudo mv kops-linux-amd64 /usr/local/bin/kops
```

* [kubefed](https://github.com/kubernetes/federation)：用來建立 Federation 控制平面與管理 Federation 叢集的工具。

Mac OS X：
```sh
$ git clone https://github.com/kubernetes/federation.git $GOPATH/src/k8s.io/federation
$ cd $GOPATH/src/k8s.io/federation
$ make quick-release
$ cp _output/dockerized/bin/linux/amd64/kubefed /usr/local/bin/kubefed
```

Linux distro：
```sh
$ wget https://storage.googleapis.com/kubernetes-federation-release/release/v1.9.0-alpha.3/federation-client-linux-amd64.tar.gz
$ tar xvf federation-client-linux-amd64.tar.gz
$ cp federation/client/bin/kubefed /usr/local/bin/
$ kubefed version
Client Version: version.Info{Major:"1", Minor:"9+", GitVersion:"v1.9.0-alpha.3", GitCommit:"85c06145286da663755b140efa2b65f793cce9ec", GitTreeState:"clean", BuildDate:"2018-02-14T12:54:40Z", GoVersion:"go1.9.1", Compiler:"gc", Platform:"linux/amd64"}
Server Version: version.Info{Major:"1", Minor:"9", GitVersion:"v1.9.6", GitCommit:"9f8ebd171479bec0ada837d7ee641dec2f8c6dd1", GitTreeState:"clean", BuildDate:"2018-03-21T15:13:31Z", GoVersion:"go1.9.3", Compiler:"gc", Platform:"linux/amd64"}
```

* [AWS CLI](https://aws.amazon.com/cli/?nc1=h_ls)：用來操作 AWS 服務的工具。

```sh
$ sudo pip install awscli
$ aws --version
aws-cli/1.15.4
```

上述工具完成後，我們還要準備一下資訊：
* 申請 AWS 帳號，並在 IAM 服務新增一個 User 設定存取所有服務(AdministratorAccess)。另外這邊要記住 AccessKey 與 SecretKey。
> 一般來說只需開啟 S3、Route53、EC2、EBS、ELB 與 VPC 就好，但由於偷懶就全開。以下為各 AWS 服務在本次安裝的用意：
> * IAM: 提供身份認證與存取管理。
> * EC2: Kubernetes 叢集部署的虛擬機環境。
> * ELB: Kubernetes 元件與 Service 負載平衡。
> * Route53: 提供 Public domain 存取 Kubernetes 環境。
> * S3: 儲存 Kops 狀態。
> * VPC: 提供 Kubernetes 與 EC2 的網路環境。

![](/images/kops/iam-user2.png)

* 擁有自己的 Domain Name，這邊可以在 AWS Route53 註冊，或者是到 GoDaddy 購買。

## 部署 Kubernetes Federation 叢集
本節將說明如何利用自己撰寫好的腳本 [aws-k8s-federation](https://github.com/kairen/aws-k8s-federation) 來部署 Kubernetes 叢集與 Federation 叢集。首先在操作節點下載：
```sh
$ git clone https://github.com/kairen/aws-k8s-federation
$ cd aws-k8s-federation
$ cp .env.sample .env
```

編輯`.env`檔案來提供後續腳本的環境變數：
```sh
# 你的 Domain Name(這邊為 <hoste_dzone_name>.<domain_name>)
export DOMAIN_NAME="k8s.example.com"

# Regions and zones
export US_WEST_REGION="us-west-2"
export US_EAST_REGION="us-east-2"
export AP_NORTHEAST_REGION="ap-northeast-1"
export ZONE="a"

# Cluster contexts name
export FED_CONTEXT="aws-fed"
export US_WEST_CONTEXT="us-west.${DOMAIN_NAME}"
export US_EAST_CONTEXT="us-east.${DOMAIN_NAME}"
export AP_NORTHEAST_CONTEXT="ap-northeast.${DOMAIN_NAME}"

# S3 buckets name
export US_WEST_BUCKET_NAME="us-west-k8s"
export US_EAST_BUCKET_NAME="us-east-k8s"
export AP_NORTHEAST_BUCKET_NAME="ap-northeast-k8s"

# Get domain name id
export HOSTED_ZONE_ID=$(aws route53 list-hosted-zones \
       | jq -r '.HostedZones[] | select(.Name=="'${DOMAIN_NAME}'.") | .Id' \
       | sed 's/\/hostedzone\///')

# Kubernetes master and node size, and node count.
export MASTER_SIZE="t2.micro"
export NODE_SIZE="t2.micro"
export NODE_COUNT="2"

# Federation simple apps deploy and service name
export DNS_RECORD_PREFIX="nginx"
export SERVICE_NAME="nginx"
```

### 建立 Route53 Hosted Zone
首先透過 aws 工具進行設定使用指定 AccessKey 與 SecretKey：
```sh
$ aws configure
AWS Access Key ID [****************QGEA]:
AWS Secret Access Key [****************zJ+w]:
Default region name [None]:
Default output format [None]:
```
> 設定的 Keys 可以在`~/.aws/credentials`找到。

接著需要在 Route53 建立一個 Hosted Zone，並在 Domain Name 供應商上設定 `NameServers`：
```sh
$ ./0-create-hosted-domain.sh
# output
...
{
    "HostedZone": {
        "ResourceRecordSetCount": 2,
        "CallerReference": "2018-04-25-16:16",
        "Config": {
            "PrivateZone": false
        },
        "Id": "/hostedzone/Z2JR49ADZ0P3WC",
        "Name": "k8s.example.com."
    },
    "DelegationSet": {
        "NameServers": [
            "ns-1547.awsdns-01.co.uk",
            "ns-1052.awsdns-03.org",
            "ns-886.awsdns-46.net",
            "ns-164.awsdns-20.com"
        ]
    },
    "Location": "https://route53.amazonaws.com/2013-04-01/hostedzone/Z2JR49ADZ0P3WC",
    "ChangeInfo": {
        "Status": "PENDING",
        "SubmittedAt": "2018-04-25T08:16:57.462Z",
        "Id": "/change/C3802PE0C1JVW2"
    }
}
```

之後將上述`NameServers`新增至自己的 Domain name 的 record 中，如 Godaddy：

![](/images/kops-fed/godday-ns.png)

### 在每個 Region 建立 Kubernetes 叢集
當 Hosted Zone 建立完成後，就可以接著建立每個 Region 的 Kubernetes 叢集，這邊腳本已包含建立叢集與 S3 Bucket 指令，因此只需要執行以下腳本即可：
```sh
$ ./1-create-clusters.sh
....
Cluster is starting.  It should be ready in a few minutes.
...
```
> 這邊會需要等待一點時間進行初始化與部署，也可以到 AWS Console 查看狀態。

完成後，即可透過 kubectl 來操作叢集：
```sh
$ ./us-east/kc get no
+ kubectl --context=us-east.k8s.example.com get no
NAME                                          STATUS    ROLES     AGE       VERSION
ip-172-20-43-26.us-east-2.compute.internal    Ready     node      1m        v1.9.3
ip-172-20-56-167.us-east-2.compute.internal   Ready     master    3m        v1.9.3
ip-172-20-63-133.us-east-2.compute.internal   Ready     node      2m        v1.9.3

$ ./ap-northeast/kc get no
+ kubectl --context=ap-northeast.k8s.example.com get no
NAME                                               STATUS    ROLES     AGE       VERSION
ip-172-20-42-184.ap-northeast-1.compute.internal   Ready     master    2m        v1.9.3
ip-172-20-52-176.ap-northeast-1.compute.internal   Ready     node      20s       v1.9.3
ip-172-20-56-88.ap-northeast-1.compute.internal    Ready     node      22s       v1.9.3

$ ./us-west/kc get no
+ kubectl --context=us-west.k8s.example.com get no
NAME                                          STATUS    ROLES     AGE       VERSION
ip-172-20-33-22.us-west-2.compute.internal    Ready     node      1m        v1.9.3
ip-172-20-55-237.us-west-2.compute.internal   Ready     master    2m        v1.9.3
ip-172-20-63-77.us-west-2.compute.internal    Ready     node      35s       v1.9.3
```

### 建立 Kubernetes Federation 叢集
當三個地區的叢集建立完成後，接著要在 US West 的叢集上部署 Federation 控制平面元件：
```sh
$ ./2-init-federation.sh
...
Federation API server is running at: abba6864f490111e8b4bd028106a7a79-793027324.us-west-2.elb.amazonaws.com

$ ./us-west/kc -n federation-system get po
+ kubectl --context=us-west.k8s.example.com -n federation-system get po
NAME                                  READY     STATUS    RESTARTS   AGE
apiserver-5d46898995-tmzvl            2/2       Running   0          1m
controller-manager-6cc78c68d5-2pbg5   0/1       Error     3          1m
```

這邊會發現`controller-manager`會一直掛掉，這是因為它需要取得 AWS 相關權限，因此需要透過 Patch 方式來把 AccessKey 與 SecretKey 注入到 Deployment 中：
```sh
$ ./3-path-federation.sh
Switched to context "us-west.k8s.example.com".
deployment "controller-manager" patched

$ ./us-west/kc -n federation-system get po
+ kubectl --context=us-west.k8s.example.com -n federation-system get po
NAME                                  READY     STATUS        RESTARTS   AGE
apiserver-5d46898995-tmzvl            2/2       Running       0          3m
controller-manager-769bd95fbc-dkssr   1/1       Running       0          21s
```

確認上述沒問題後，透過 kubectl 確認 contexts：
```sh
$ kubectl config get-contexts
CURRENT   NAME                           CLUSTER                        AUTHINFO                       NAMESPACE
          ap-northeast.k8s.example.com   ap-northeast.k8s.example.com   ap-northeast.k8s.example.com
          aws-fed                        aws-fed                        aws-fed
          us-east.k8s.example.com        us-east.k8s.example.com        us-east.k8s.example.com
*         us-west.k8s.example.com        us-west.k8s.example.com        us-west.k8s.example.com
```

接著透過以下腳本來加入`us-west`叢集至 aws-fed 的 Federation 中：
```sh
$ ./4-join-us-west.sh
+ kubectl config use-context aws-fed
Switched to context "aws-fed".
+ kubefed join us-west --host-cluster-context=us-west.k8s.example.com --cluster-context=us-west.k8s.example.com
cluster "us-west" created
```

加入`ap-northeast`叢集至 aws-fed 的 Federation 中：
```sh
$ ./5-join-ap-northeast.sh
+ kubectl config use-context aws-fed
Switched to context "aws-fed".
+ kubefed join ap-northeast --host-cluster-context=us-west.k8s.example.com --cluster-context=ap-northeast.k8s.example.com
cluster "ap-northeast" created
```

加入`us-east`叢集至 aws-fed 的 Federation 中：
```sh
$ ./6-join-us-east.sh
+ kubectl config use-context aws-fed
Switched to context "aws-fed".
+ kubefed join us-east --host-cluster-context=us-west.k8s.example.com --cluster-context=us-east.k8s.example.com
cluster "us-east" created
```

完成後，在 Federation 建立 Federated Namespace，並列出叢集：
```sh
$ ./7-create-fed-ns.sh
+ kubectl --context=aws-fed create namespace default
namespace "default" created
+ kubectl --context=aws-fed get clusters
NAME           AGE
ap-northeast   2m
us-east        1m
us-west        2m
```

完成這些過程表示你已經建立了一套 Kubernetes Federation 叢集了，接下來就可以進行測試。

## 測試叢集
首先建立一個簡單的 Nginx 來提供服務的測試，這邊可以透過以下腳本達成：
```sh
$ ./8-deploy-fed-nginx.sh
+ cat
+ kubectl --context=aws-fed apply -f -
deployment "nginx" created
+ cat
+ kubectl --context=aws-fed apply -f -
service "nginx" created

$ kubectl get deploy,svc
NAME           DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
deploy/nginx   3         3         3            3           3m

NAME        TYPE           CLUSTER-IP   EXTERNAL-IP        PORT(S)   AGE
svc/nginx   LoadBalancer   <none>       a4d86547a4903...   80/TCP    2m
```
> 這裡的 nginx deployment 有設定`deployment-preferences`，因此在 scale 時會依據下面資訊來分配：
```sh
{
       "rebalance": true,
       "clusters": {
         "us-west": {
           "minReplicas": 2,
           "maxReplicas": 10,
           "weight": 200
         },
         "us-east": {
           "minReplicas": 0,
           "maxReplicas": 2,
           "weight": 150
         },
         "ap-northeast": {
           "minReplicas": 1,
           "maxReplicas": 5,
           "weight": 150
         }
       }
     }
```

檢查每個叢集的 Pod：
```sh
# us-west context(這邊策略為 2 - 10)
$ ./us-west/kc get po
+ kubectl --context=us-west.k8s.example.com get po
NAME                     READY     STATUS    RESTARTS   AGE
nginx-679dc9c764-4x78c   1/1       Running   0          3m
nginx-679dc9c764-fzv9z   1/1       Running   0          3m

# us-east context(這邊策略為 0 - 2)
$ ./us-east/kc get po
+ kubectl --context=us-east.k8s.example.com get po
No resources found.

# ap-northeast context(這邊策略為 1 - 5)
$ ./ap-northeast/kc get po
+ kubectl --context=ap-northeast.k8s.example.com get po
NAME                     READY     STATUS    RESTARTS   AGE
nginx-679dc9c764-hmwzq   1/1       Running   0          4m
```

透過擴展副本數來查看分配狀況：
```sh
$ ./9-scale-fed-nginx.sh
+ kubectl --context=aws-fed scale deploy nginx --replicas=10
deployment "nginx" scaled

$ kubectl get deploy
NAME      DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
nginx     10        10        10           10          8m
```

再次檢查每個叢集的 Pod：
```sh
# us-west context(這邊策略為 2 - 10)
$ ./us-west/kc get po
+ kubectl --context=us-west.k8s.example.com get po
NAME                     READY     STATUS    RESTARTS   AGE
nginx-679dc9c764-4x78c   1/1       Running   0          8m
nginx-679dc9c764-7958k   1/1       Running   0          50s
nginx-679dc9c764-fzv9z   1/1       Running   0          8m
nginx-679dc9c764-j6kc9   1/1       Running   0          50s
nginx-679dc9c764-t6rvj   1/1       Running   0          50s

# us-east context(這邊策略為 0 - 2)
$ ./us-east/kc get po
+ kubectl --context=us-east.k8s.example.com get po
NAME                     READY     STATUS    RESTARTS   AGE
nginx-679dc9c764-8t7qz   1/1       Running   0          1m
nginx-679dc9c764-zvqmx   1/1       Running   0          1m

# ap-northeast context(這邊策略為 1 - 5)
$ ./ap-northeast/kc get po
+ kubectl --context=ap-northeast.k8s.example.com get po
NAME                     READY     STATUS    RESTARTS   AGE
nginx-679dc9c764-f79v7   1/1       Running   0          1m
nginx-679dc9c764-hmwzq   1/1       Running   0          9m
nginx-679dc9c764-vj7hb   1/1       Running   0          1m
```
> 可以看到結果符合我們預期範圍內。

最後因為服務是透過 ELB 來提供，為了統一透過 Domain name 存取相同服務，這邊更新 Hosted Zone Record 來轉發：
```sh
$ ./10-update-fed-nginx-record.sh
```

完成後透過 cURL 工作來測試：
```sh
$ curl nginx.k8s.example.com
...
<title>Welcome to nginx!</title>
...
```

最後透過該腳本來清楚叢集與 AWS 服務上建立的東西：
```sh
$ ./99-purge.sh
```
