---
title: 使用 Kuryr 與 Kubernetes 網路整合
layout: default
date: 2016-08-22 16:23:01
categories:
- OpenStack
- Kubernetes
tags:
- OpenStack
- Kubernetes
- CNI
- Docker
---

```sh
$ openstack network create k8s-pod-net
$ openstack subnet create \
                   --network k8s-pod-net \
                   --dns-nameserver 8.8.4.4 \
                   --gateway 10.244.0.1 \
                   --subnet-range 10.244.0.0/16 k8s-pod-subnet

$ openstack network create k8s-service-net
$ openstack subnet create \
                   --network k8s-service-net \
                   --dns-nameserver 8.8.4.4 \
                   --gateway 192.160.0.1 \
                   --subnet-range 192.160.0.0/12 k8s-service-subnet
```

```sh
$ openstack security group create \
    --project admin service_pod_access

$ openstack security group rule create \
      --project admin \
      --remote-ip 192.160.0.0/12 \
      --ethertype IPv4 \
      --protocol tcp \
      service_pod_access
```
