---
title: 使用 Kops 部署 Kubernetes 至公有雲(AWS)
date: 2018-04-18 17:08:54
layout: page
categories:
- Kubernetes
tags:
- Kubernetes
- AWS
---
[Kops](https://github.com/kubernetes/kops) 是 Kubernetes 官方維護的專案，是一套 Production ready 的 Kubernetes 部署、升級與管理工具，早期用於 AWS 公有雲上建置 Kubernetes 叢集使用，但隨著社群的推進已支援 GCP、vSphere(Alpha)，未來也會有更多公有雲平台慢慢被支援(Maybe)。本篇簡單撰寫使用 Kops 部署一個叢集，過去自己因為公司都是屬於建置 On-premises 的 Kubernetes，因此很少使用 Kops，剛好最近社群分享又再一次接觸的關析，所以就來寫個文章。

本次安裝的軟體版本：
* Kubernetes v1.9.3
* Kops v1.9.0

<!--more-->

## 事前準備
開始使用 Kops 前，需要先安裝下列工具到操作機器上來提供使用：
* [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)：用來操作部署完成的 Kubernetes 叢集。
* [kops](https://github.com/kubernetes/kops)：本次使用工具，用來部署與管理公有雲上的 Kubernetes 叢集。

Mac OS X：
```sh
$ brew update && brew install kops
```

Linux distro：
```sh
$ curl -LO https://github.com/kubernetes/kops/releases/download/$(curl -s https://api.github.com/repos/kubernetes/kops/releases/latest | grep tag_name | cut -d '"' -f 4)/kops-linux-amd64
$ chmod +x kops-linux-amd64 && sudo mv kops-linux-amd64 /usr/local/bin/kops
```

* [AWS CLI](https://aws.amazon.com/cli/?nc1=h_ls)：用來操作 AWS 服務的工具。

```sh
$ sudo pip install awscli
$ aws --version
aws-cli/1.15.4
```

上述工具完成後，我們還要準備一下資訊：
* 申請 AWS 帳號，並在 IAM 服務新增一個 User 設定存取所有服務(AdministratorAccess)。另外這邊要記住 AccessKey 與 SecretKey。
> 一般來說只需開啟 S3、Route53、EC2、EBS 與 ELB 就好，但由於偷懶就全開。

![](/images/kops/iam-user2.png)

* 擁有自己的 Domain Name，這邊可以在 AWS Route53 註冊，或者是到 GoDaddy 購買。

## 建立 S3 Bucket 與 Route53 Hosted Zone
首先透過 aws 工具進行設定使用指定 AccessKey 與 SecretKey：
```sh
$ aws configure
AWS Access Key ID [****************QGEA]:
AWS Secret Access Key [****************zJ+w]:
Default region name [None]:
Default output format [None]:
```
> 設定的 Keys 可以在`~/.aws/credentials`找到。

完成後建立一個 S3 bucket 用來儲存 Kops 狀態：
```sh
$ aws s3 mb s3://kops-k8s-1 --region us-west-2
make_bucket: kops-k8s-1
```
> 這邊 region 可自行選擇，這邊選用 Oregon。

接著建立一個 Route53 Hosted Zone：
```sh
$ aws route53 create-hosted-zone \
    --name k8s.example.com \
    --caller-reference $(date '+%Y-%m-%d-%H:%M')

# output
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
> 請修改`--name`為自己所擁有的 domain name。

之後將上述`NameServers`新增至自己的 Domain name 的 record 中，如 Godaddy：

![](/images/kops/route53-hostedzone.png)

## 部署 Kubernetes 叢集
當上述階段完成後，在自己機器建立 SSH key，就可以使用 Kops 來建立 Kubernetes 叢集：
```sh
$ ssh-keygen -t rsa
$ kops create cluster \
    --name=k8s.example.com \
    --state=s3://kops-k8s-1 \
    --zones=us-west-2a \
    --master-size=t2.micro \
    --node-size=t2.micro \
    --node-count=2 \
    --dns-zone=k8s.example.com

# output
...
Finally configure your cluster with: kops update cluster k8s.example.com --yes
```

若過程沒有發生錯誤的話，最後會提示再執行 update 來正式進行部署：
```sh
$ kops update cluster k8s.example.com --state=s3://kops-k8s-1 --yes
# output
...
Cluster is starting.  It should be ready in a few minutes.
```

當看到上述資訊時，表示叢集已建立，這時候等待環境初始化完成後就可以使用 kubectl 來操作：
```sh
$ kubectl get node
NAME                                          STATUS    ROLES     AGE       VERSION
ip-172-20-32-194.us-west-2.compute.internal   Ready     master    1m        v1.9.3
ip-172-20-32-21.us-west-2.compute.internal    Ready     node      22s       v1.9.3
ip-172-20-54-100.us-west-2.compute.internal   Ready     node      28s       v1.9.3
```

## 測試
完成後就可以進行功能測試，這邊簡單建立 Nginx app：
```sh
$ kubectl run nginx --image nginx --port 80
$ kubectl expose deploy nginx --type=LoadBalancer --port 80
$ kubectl get po,svc
NAME                        READY     STATUS    RESTARTS   AGE
po/nginx-7587c6fdb6-7qtlr   1/1       Running   0          50s

NAME             TYPE           CLUSTER-IP    EXTERNAL-IP        PORT(S)        AGE
svc/kubernetes   ClusterIP      100.64.0.1    <none>             443/TCP        8m
svc/nginx        LoadBalancer   100.68.96.3   ad99f206f486e...   80:30174/TCP   28s
```

這邊會看到`EXTERNAL-IP`會直接透過 AWS ELB 建立一個 Load Balancer，這時只要更新 Route53 的 record set 就可以存取到服務：
```sh
$ export DOMAIN_NAME=k8s.example.com
$ export NGINX_LB=$(kubectl get svc/nginx \
  --template="{{range .status.loadBalancer.ingress}} {{.hostname}} {{end}}")

$ cat <<EOF > dns-record.json
{
  "Comment": "Create/Update a latency-based CNAME record for a federated Deployment",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "nginx.${DOMAIN_NAME}",
        "Type": "CNAME",
        "Region": "us-west-2",
        "TTL": 300,
        "SetIdentifier": "us-west-2",
        "ResourceRecords": [
          {
            "Value": "${NGINX_LB}"
          }
        ]
      }
    }
  ]
}
EOF

$ export HOSTED_ZONE_ID=$(aws route53 list-hosted-zones \
       | jq -r '.HostedZones[] | select(.Name=="'${DOMAIN_NAME}'.") | .Id' \
       | sed 's/\/hostedzone\///')

$ aws route53 change-resource-record-sets \
    --hosted-zone-id ${HOSTED_ZONE_ID} \
    --change-batch file://dns-record.json

# output
{
    "ChangeInfo": {
        "Status": "PENDING",
        "Comment": "Create/Update a latency-based CNAME record for a federated Deployment",
        "SubmittedAt": "2018-04-25T10:06:02.545Z",
        "Id": "/change/C79MFJRHCF05R"
    }
}
```

完成後透過 cURL 工作來測試：
```sh
$ curl nginx.k8s.example.com
...
<title>Welcome to nginx!</title>
...
```

## 刪除節點
當叢集測完後，可以利用以下指令來刪除：
```sh
$ kops delete cluster \
 --name=k8s.example.com \
 --state=s3://kops-k8s-1 --yes

Deleted cluster: "k8s.k2r2bai.com"

$ aws s3 rb s3://kops-k8s-1 --force
remove_bucket: kops-k8s-1
```

接著清除 Route53 所有 record 並刪除 hosted zone：
```sh
$ aws route53 list-resource-record-sets \
  --hosted-zone-id ${HOSTED_ZONE_ID} |
jq -c '.ResourceRecordSets[]' |
while read -r resourcerecordset; do
  read -r name type <<<$(echo $(jq -r '.Name,.Type' <<<"$resourcerecordset"))
  if [ $type != "NS" -a $type != "SOA" ]; then
    aws route53 change-resource-record-sets \
      --hosted-zone-id ${HOSTED_ZONE_ID} \
      --change-batch '{"Changes":[{"Action":"DELETE","ResourceRecordSet":
          '"$resourcerecordset"'
        }]}' \
      --output text --query 'ChangeInfo.Id'
  fi
done

$ aws route53 delete-hosted-zone --id ${HOSTED_ZONE_ID}
```
