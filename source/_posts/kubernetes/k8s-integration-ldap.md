---
title: 整合 Open LDAP 進行 Kubernetes 身份認證
date: 2018-4-15 17:08:54
catalog: true
categories:
- Kubernetes
tags:
- Kubernetes
- LDAP
---
本文將說明如何整合 OpenLDAP 來提供給 Kubernetes 進行使用者認證。Kubernetes 官方並沒有提供針對 LDAP 與 AD 的整合，但是可以藉由 [Webhook Token Authentication](https://kubernetes.io/docs/admin/authentication/#webhook-token-authentication) 以及 [Authenticating Proxy](https://kubernetes.io/docs/admin/authentication/#authenticating-proxy) 來達到整合功能。概念是開發一個 HTTP Server 提供 POST Method 來塞入 Bearer Token，而該 HTTP Server 利用 LDAP library 檢索對應 Token 的 User 進行認證，成功後回傳該 User 的所有 Group 等資訊，而這時可以利用 Kubernetes 針對該 User 的 Group 設定對應的 RBAC role 進行權限控管。

<!--more-->

## 節點資訊
本教學將以下列節點數與規格來進行部署 Kubernetes 叢集，作業系統可採用`Ubuntu 16.x`與`CentOS 7.x`：

| IP Address | Hostname   | CPU | Memory |
|------------|------------|-----|--------|
|192.16.35.11| k8s-m1     | 1   | 2G     |
|192.16.35.12| k8s-n1     | 1   | 2G     |
|192.16.35.13| k8s-n2     | 1   | 2G     |
|192.16.35.20| ldap-server| 1   | 1G     |

> * 這邊`m`為 K8s master，`n`為 K8s node。
> * 所有操作全部用`root`使用者進行(方便用)，以 SRE 來說不推薦。
> * 可以下載 [Vagrantfile](https://kairen.github.io/files/k8s-ldap/Vagrantfile) 來建立 Virtualbox 虛擬機叢集。不過需要注意機器資源是否足夠。

## 事前準備
開始安裝前需要確保以下條件已達成：
* `所有節點`需要安裝 Docker CE 版本的容器引擎：

```sh
$ curl -fsSL "https://get.docker.com/" | sh
```
> 不管是在 `Ubuntu` 或 `CentOS` 都只需要執行該指令就會自動安裝最新版 Docker。
> CentOS 安裝完成後需要再執行以下指令：
```sh
$ systemctl enable docker && systemctl start docker
```

* 所有節點以 kubeadm 部署成 Kubernetes v1.9+ 叢集。請參考 [用 kubeadm 部署 Kubernetes 叢集](https://kairen.github.io/2016/09/29/kubernetes/deploy/kubeadm/)。

## OpenLDAP 與 phpLDAPadmin
本節將說明如何部署、設定與操作 OpenLDAP。

### 部署
進入`ldap-server`節點透過 Docker 來進行部署：
```sh
$ docker run -d \
    -p 389:389 -p 636:636 \
    --env LDAP_ORGANISATION="Kubernetes LDAP" \
    --env LDAP_DOMAIN="k8s.com" \
    --env LDAP_ADMIN_PASSWORD="password" \
    --env LDAP_CONFIG_PASSWORD="password" \
    --name openldap-server \
    osixia/openldap:1.2.0

$ docker run -d \
    -p 443:443 \
    --env PHPLDAPADMIN_LDAP_HOSTS=192.16.35.20 \
    --name phpldapadmin \
    osixia/phpldapadmin:0.7.1
```
> 這邊為`cn=admin,dc=k8s,dc=com`為`admin` DN ，而`cn=admin,cn=config`為`config`。另外這邊僅做測試用，故不使用 Persistent Volumes，需要可以參考 [Docker OpenLDAP](https://github.com/osixia/docker-openldap)。

完成後就可以透過瀏覽器來 [phpLDAPadmin website](https://192.16.35.20/)。這邊點選`Login`輸入 DN 與 Password。
![](/images/k8s-ldap/ldap-login.png)

成功登入後畫面，這時可以自行新增其他資訊。
![](/images/k8s-ldap/ldap-logined.png)

### 建立 Kubenretes Token Schema
進入`openldap-server 容器`，接著建立 Kubernetes token schema 物件的設定檔：
```sh
$ docker exec -ti openldap-server sh
$ mkdir ~/kubernetes_tokens
$ cat <<EOF > ~/kubernetes_tokens/kubernetesToken.schema
attributeType ( 1.3.6.1.4.1.18171.2.1.8
        NAME 'kubernetesToken'
        DESC 'Kubernetes authentication token'
        EQUALITY caseExactIA5Match
        SUBSTR caseExactIA5SubstringsMatch
        SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 SINGLE-VALUE )

objectClass ( 1.3.6.1.4.1.18171.2.3
        NAME 'kubernetesAuthenticationObject'
        DESC 'Object that may authenticate to a Kubernetes cluster'
        AUXILIARY
        MUST kubernetesToken )
EOF

$ echo "include /root/kubernetes_tokens/kubernetesToken.schema" > ~/kubernetes_tokens/schema_convert.conf
$ slaptest -f ~/kubernetes_tokens/schema_convert.conf -F ~/kubernetes_tokens
config file testing succeeded
```

修改以下檔案內容，如以下所示：
```sh
$ vim ~/kubernetes_tokens/cn=config/cn=schema/cn\=\{0\}kubernetestoken.ldif
# AUTO-GENERATED FILE - DO NOT EDIT!! Use ldapmodify.
# CRC32 e502306e
dn: cn=kubernetestoken,cn=schema,cn=config
objectClass: olcSchemaConfig
cn: kubernetestoken
olcAttributeTypes: {0}( 1.3.6.1.4.1.18171.2.1.8 NAME 'kubernetesToken' DESC
 'Kubernetes authentication token' EQUALITY caseExactIA5Match SUBSTR caseExa
 ctIA5SubstringsMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 SINGLE-VALUE )
olcObjectClasses: {0}( 1.3.6.1.4.1.18171.2.3 NAME 'kubernetesAuthenticationO
 bject' DESC 'Object that may authenticate to a Kubernetes cluster' AUXILIAR
 Y MUST kubernetesToken )
```

新增 Schema 物件至 LDAP Server 中：
```sh
$ cd ~/kubernetes_tokens/cn=config/cn=schema
$ ldapadd -c -Y EXTERNAL -H ldapi:/// -f cn\=\{0\}kubernetestoken.ldif
SASL/EXTERNAL authentication started
SASL username: gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth
SASL SSF: 0
adding new entry "cn=kubernetestoken,cn=schema,cn=config"
```

完成後查詢是否成功新增 Entry：
```sh
$ ldapsearch -x -H ldap:/// -LLL -D "cn=admin,cn=config" -w password -b "cn=schema,cn=config" "(objectClass=olcSchemaConfig)" dn -Z
Enter LDAP Password:
dn: cn=schema,cn=config
...
dn: cn={14}kubernetestoken,cn=schema,cn=config
```

### 新增測試用 LDAP Groups 與 Users
當上面 Schema 建立完成後，這邊需要新增一些測試用 Groups：
```sh
$ cat <<EOF > groups.ldif
dn: ou=People,dc=k8s,dc=com
ou: People
objectClass: top
objectClass: organizationalUnit
description: Parent object of all UNIX accounts

dn: ou=Groups,dc=k8s,dc=com
ou: Groups
objectClass: top
objectClass: organizationalUnit
description: Parent object of all UNIX groups

dn: cn=kubernetes,ou=Groups,dc=k8s,dc=com
cn: kubernetes
gidnumber: 100
memberuid: user1
memberuid: user2
objectclass: posixGroup
objectclass: top
EOF

$ ldapmodify -x -a -H ldap:// -D "cn=admin,dc=k8s,dc=com" -w password -f groups.ldif
adding new entry "ou=People,dc=k8s,dc=com"

adding new entry "ou=Groups,dc=k8s,dc=com"

adding new entry "cn=kubernetes,ou=Groups,dc=k8s,dc=com"
```

Group 建立完成後再接著建立 User：
```sh
$ cat <<EOF > users.ldif
dn: uid=user1,ou=People,dc=k8s,dc=com
cn: user1
gidnumber: 100
givenname: user1
homedirectory: /home/users/user1
loginshell: /bin/sh
objectclass: inetOrgPerson
objectclass: posixAccount
objectclass: top
objectClass: shadowAccount
objectClass: organizationalPerson
sn: user1
uid: user1
uidnumber: 1000
userpassword: user1

dn: uid=user2,ou=People,dc=k8s,dc=com
homedirectory: /home/users/user2
loginshell: /bin/sh
objectclass: inetOrgPerson
objectclass: posixAccount
objectclass: top
objectClass: shadowAccount
objectClass: organizationalPerson
cn: user2
givenname: user2
sn: user2
uid: user2
uidnumber: 1001
gidnumber: 100
userpassword: user2
EOF

$ ldapmodify -x -a -H ldap:// -D "cn=admin,dc=k8s,dc=com" -w password -f users.ldif
adding new entry "uid=user1,ou=People,dc=k8s,dc=com"

adding new entry "uid=user2,ou=People,dc=k8s,dc=com"
```

這邊可以登入 phpLDAPadmin 查看，結果如以下所示：
![](/images/k8s-ldap/ldap-entry.png)

確認沒問題後，將 User dump 至一個文字檔案中：
```sh
$ cat <<EOF > users.txt
dn: uid=user1,ou=People,dc=k8s,dc=com
dn: uid=user2,ou=People,dc=k8s,dc=com
EOF
```
> 這邊偷懶直接用 cat。

執行以下腳本來更新每個 LDAP User 的 kubernetesToken：
```sh
$ while read -r user; do
fname=$(echo $user | grep -E -o "uid=[a-z0-9]+" | cut -d"=" -f2)
token=$(dd if=/dev/urandom bs=128 count=1 2>/dev/null | base64 | tr -d "=+/" | dd bs=32 count=1 2>/dev/null)
cat << EOF > "${fname}.ldif"
$user
changetype: modify
add: objectClass
objectclass: kubernetesAuthenticationObject
-
add: kubernetesToken
kubernetesToken: $token
EOF

ldapmodify -a -H ldapi:/// -D "cn=admin,dc=k8s,dc=com" -w password  -f "${fname}.ldif"
done < users.txt

# output
Enter LDAP Password:
modifying entry "uid=user1,ou=Users,dc=k8s,dc=com"

Enter LDAP Password:
modifying entry "uid=user2,ou=Users,dc=k8s,dc=com"
```

## 部署 Kubernetes LDAP
當 Kubernetes 環境建立完成後，首先進入`k8s-m1`節點，透過 git 取得 kube-ldap-authn 原始碼專案：
```sh
$ git clone https://github.com/kairen/kube-ldap-authn.git
$ cd kube-ldap-authn
```
> 若想使用 Go 語言實作的版本，可以參考 [kube-ldap-webhook](https://github.com/kairen/kube-ldap-webhook).

新增一個`config.py`檔案來提供相關設定內容：
```sh
LDAP_URL='ldap://192.16.35.20/ ldap://192.16.35.20'
LDAP_START_TLS = False
LDAP_BIND_DN = 'cn=admin,dc=k8s,dc=com'
LDAP_BIND_PASSWORD = 'password'
LDAP_USER_NAME_ATTRIBUTE = 'uid'
LDAP_USER_UID_ATTRIBUTE = 'uidNumber'
LDAP_USER_SEARCH_BASE = 'ou=People,dc=k8s,dc=com'
LDAP_USER_SEARCH_FILTER = "(&(kubernetesToken={token}))"
LDAP_GROUP_NAME_ATTRIBUTE = 'cn'
LDAP_GROUP_SEARCH_BASE = 'ou=Groups,dc=k8s,dc=com'
LDAP_GROUP_SEARCH_FILTER = '(|(&(objectClass=posixGroup)(memberUid={username}))(&(member={dn})(objectClass=groupOfNames)))'
```
> 變數詳細說明可以參考 [Config example](https://github.com/kairen/kube-ldap-authn/blob/master/config.py.example)

建立 kube-ldap-authn secret 來提供給 pod 使用，並部署 kube-ldap-authn pod 到所有 master 節點上：
```sh
$ kubectl -n kube-system create secret generic ldap-authn-config --from-file=config.py=config.py
$ kubectl create -f daemonset.yaml
$ kubectl -n kube-system get po -l app=kube-ldap-authn -o wide
NAME                    READY     STATUS    RESTARTS   AGE       IP             NODE
kube-ldap-authn-sx994   1/1       Running   0          13s       192.16.35.11   k8s-m1
```

這邊若成功部署的話，可以用 curl 進行測試：
```sh
$ curl -X POST -H "Content-Type: application/json" \
    -d '{"apiVersion": "authentication.k8s.io/v1beta1", "kind": "TokenReview",  "spec": {"token": "<LDAP_K8S_TOKEN>"}}' \
    http://localhost:8087/authn

# output
{
  "apiVersion": "authentication.k8s.io/v1beta1",
  "kind": "TokenReview",
  "status": {
    "authenticated": true,
    "user": {
      "groups": [
        "kubernetes"
      ],
      "uid": "1000",
      "username": "user1"
    }
  }
}
```

在所有`master`節點上新增一個名稱為`/srv/kubernetes/webhook-authn`的檔案，並加入以下內容：
```sh
$ mkdir /srv/kubernetes
$ cat <<EOF > /srv/kubernetes/webhook-authn
clusters:
  - name: ldap-authn
    cluster:
      server: http://localhost:8087/authn
users:
  - name: apiserver
current-context: webhook
contexts:
- context:
    cluster: ldap-authn
    user: apiserver
  name: webhook
EOF
```

修改所有`master`節點上的`kube-apiserver.yaml` Static Pod 檔案，該檔案會存在於`/etc/kubernetes/manifests`目錄中，請修改加入以下內容：
```yaml
...
spec:
  containers:
  - command:
    ...
    - --runtime-config=authentication.k8s.io/v1beta1=true
    - --authentication-token-webhook-config-file=/srv/kubernetes/webhook-authn
    - --authentication-token-webhook-cache-ttl=5m
    volumeMounts:
      ...
    - mountPath: /srv/kubernetes/webhook-authn
      name: webhook-authn
      readOnly: true
  volumes:
    ...
  - hostPath:
      path: /srv/kubernetes/webhook-authn
      type: File
    name: webhook-authn
```
> 這邊`...`表示已存在的內容，請不要刪除與變更。這邊也可以用 kubeadmconfig 來設定，請參考 [Using kubeadm init with a configuration file](https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init/#config-file)。

## 測試功能
首先進入`k8s-m1`，建立一個綁定在 user1 namespace 的唯讀 Role 與 RoleBinding：
```sh
$ kubectl create ns user1

# 建立 Role
$ cat <<EOF | kubectl create -f -
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: readonly-role
  namespace: user1
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "watch", "list"]
EOF

# 建立 RoleBinding
$ cat <<EOF | kubectl create -f -
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: readonly-role-binding
  namespace: user1
subjects:
- kind: Group
  name: kubernetes
  apiGroup: ""
roleRef:
  kind: Role
  name: readonly-role
  apiGroup: ""
EOF
```
> 注意!!這邊的`Group`是 LDAP 中的 Group。

在任意台 Kubernetes client 端設定 Kubeconfig 來存取叢集，這邊直接在`k8s-m1`進行：
```sh
$ cd
$ kubectl config set-credentials user1 --kubeconfig=.kube/config --token=<user-ldap-token>
$ kubectl config set-context user1-context \
    --kubeconfig=.kube/config \
    --cluster=kubernetes \
    --namespace=user1 --user=user1
```

接著透過 kubeclt 來測試權限是否正確設定：
```sh
$ kubectl --context=user1-context get po
No resources found

$ kubectl --context=user1-context run nginx --image nginx --port 80
Error from server (Forbidden): deployments.extensions is forbidden: User "user1" cannot create deployments.extensions in the namespace "user1"

$ kubectl --context=user1-context get po -n default
Error from server (Forbidden): pods is forbidden: User "user1" cannot list pods in the namespace "default"
```

## 參考資料
- https://github.com/osixia/docker-openldap
- https://icicimov.github.io/blog/virtualization/Kubernetes-LDAP-Authentication/
- https://github.com/torchbox/kube-ldap-authn
