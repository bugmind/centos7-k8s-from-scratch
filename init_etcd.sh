sudo -i

# 无密码 ssh 登录其它节点
yum install -y sshpass
ssh-keygen -f $HOME/.ssh/id_rsa -t rsa -N ''
sshpass -p vagrant ssh-copy-id -o "StrictHostKeyChecking no" root@172.27.129.105
sshpass -p vagrant ssh-copy-id -o "StrictHostKeyChecking no" root@kube-node1
sshpass -p vagrant ssh-copy-id -o "StrictHostKeyChecking no" root@kube-node2
sshpass -p vagrant ssh-copy-id -o "StrictHostKeyChecking no" root@kube-node3

sshpass -p k8s ssh-copy-id -o "StrictHostKeyChecking no" k8s@172.27.129.105
sshpass -p k8s ssh-copy-id -o "StrictHostKeyChecking no" k8s@kube-node1
sshpass -p k8s ssh-copy-id -o "StrictHostKeyChecking no" k8s@kube-node2
sshpass -p k8s ssh-copy-id -o "StrictHostKeyChecking no" k8s@kube-node3

# 集群环境变量
cat <<EOF > environment.sh
#!/usr/bin/bash

# 生成 EncryptionConfig 所需的加密 key
ENCRYPTION_KEY=\$(head -c 32 /dev/urandom | base64)

# 最好使用 当前未用的网段 来定义服务网段和 Pod 网段

# 服务网段，部署前路由不可达，部署后集群内路由可达(kube-proxy 和 ipvs 保证)
SERVICE_CIDR="10.254.0.0/16"

# Pod 网段，建议 /16 段地址，部署前路由不可达，部署后集群内路由可达(flanneld 保证)
CLUSTER_CIDR="172.30.0.0/16"

# 服务端口范围 (NodePort Range)
export NODE_PORT_RANGE="8400-9000"

# 集群各机器 IP 数组
export NODE_IPS=(172.27.129.105 172.27.129.111 172.27.129.112)

# 集群各 IP 对应的 主机名数组
export NODE_NAMES=(kube-node1 kube-node2 kube-node3)

# kube-apiserver 节点 IP
export MASTER_IP=172.27.129.105

# kube-apiserver https 地址
export KUBE_APISERVER="https://\${MASTER_IP}:6443"

# etcd 集群服务地址列表
export ETCD_ENDPOINTS="https://172.27.129.105:2379,https://172.27.129.111:2379,https://172.27.129.112:2379"

# etcd 集群间通信的 IP 和端口
export ETCD_NODES="kube-node1=https://172.27.129.105:2380,kube-node2=https://172.27.129.111:2380,kube-node3=https://172.27.129.112:2380"

# flanneld 网络配置前缀
export FLANNEL_ETCD_PREFIX="/kubernetes/network"

# kubernetes 服务 IP (一般是 SERVICE_CIDR 中第一个IP)
export CLUSTER_KUBERNETES_SVC_IP="10.254.0.1"

# 集群 DNS 服务 IP (从 SERVICE_CIDR 中预分配)
export CLUSTER_DNS_SVC_IP="10.254.0.2"

# 集群 DNS 域名
export CLUSTER_DNS_DOMAIN="cluster.local."

# 将二进制目录 /opt/k8s/bin 加到 PATH 中
export PATH=/opt/k8s/bin:\$PATH
EOF

source environment.sh
for node_ip in ${NODE_IPS[@]}
  do
    echo "environment.sh >>> ${node_ip}"
    scp environment.sh k8s@${node_ip}:/opt/k8s/bin/
    ssh k8s@${node_ip} "chmod +x /opt/k8s/bin/*"
  done

# 安装 cfssl 工具集
mkdir -p /opt/k8s/cert && chown -R k8s /opt/k8s && cd /opt/k8s
#curl -o /opt/k8s/bin/cfssl https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
#curl -o /opt/k8s/bin/cfssljson https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
#curl -o /opt/k8s/bin/cfssl-certinfo https://pkg.cfssl.org/R1.2/cfssl-certinfo_linux-amd64
cp /vagrant/cfssl* /opt/k8s/bin/
chown k8s /opt/k8s/bin/cfssl*
chmod +x /opt/k8s/bin/*
export PATH=/opt/k8s/bin:$PATH

# 创建配置文件
cat > ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "87600h"
    },
    "profiles": {
      "kubernetes": {
        "usages": [
            "signing",
            "key encipherment",
            "server auth",
            "client auth"
        ],
        "expiry": "87600h"
      }
    }
  }
}
EOF

# 创建证书签名请求文件
cat > ca-csr.json <<EOF
{
  "CN": "kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "k8s",
      "OU": "4Paradigm"
    }
  ]
}
EOF

# 生成 CA 证书和私钥
cfssl gencert -initca ca-csr.json | cfssljson -bare ca
ls ca*
source /opt/k8s/bin/environment.sh # 导入 NODE_IPS 环境变量
for node_ip in ${NODE_IPS[@]}
  do
    echo "ca*.pem ca-config.json >>> ${node_ip}"
    scp ca*.pem ca-config.json k8s@${node_ip}:/etc/kubernetes/cert
  done

# 下载和分发 kubectl 二进制文件
# curl -OL https://dl.k8s.io/v1.10.4/kubernetes-client-linux-amd64.tar.gz
cp /vagrant/kubernetes-client-linux-amd64.tar.gz .
tar -zxf kubernetes-client-linux-amd64.tar.gz
source /opt/k8s/bin/environment.sh # 导入 NODE_IPS 环境变量
for node_ip in ${NODE_IPS[@]}
  do
    echo "${USER}::kubernetes/client/bin/kubectl >>> ${node_ip}"
    scp kubernetes/client/bin/kubectl k8s@${node_ip}:/opt/k8s/bin/
    ssh k8s@${node_ip} "chmod +x /opt/k8s/bin/*"
  done

# 创建 admin 证书和私钥
cat > admin-csr.json <<EOF
{
  "CN": "admin",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "system:masters",
      "OU": "4Paradigm"
    }
  ]
}
EOF
# 生成证书和私钥：
cfssl gencert -ca=/etc/kubernetes/cert/ca.pem \
  -ca-key=/etc/kubernetes/cert/ca-key.pem \
  -config=/etc/kubernetes/cert/ca-config.json \
  -profile=kubernetes admin-csr.json | cfssljson -bare admin
ls admin*

# 创建 kubeconfig 文件
source /opt/k8s/bin/environment.sh
# 设置集群参数
kubectl config set-cluster kubernetes \
  --certificate-authority=/etc/kubernetes/cert/ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=kubectl.kubeconfig

# 设置客户端认证参数
kubectl config set-credentials admin \
  --client-certificate=admin.pem \
  --client-key=admin-key.pem \
  --embed-certs=true \
  --kubeconfig=kubectl.kubeconfig

# 设置上下文参数
kubectl config set-context kubernetes \
  --cluster=kubernetes \
  --user=admin \
  --kubeconfig=kubectl.kubeconfig

# 设置默认上下文
kubectl config use-context kubernetes --kubeconfig=kubectl.kubeconfig

source /opt/k8s/bin/environment.sh # 导入 NODE_IPS 环境变量
for node_ip in ${NODE_IPS[@]}
  do
    echo "kubectl.kubeconfig >>> ${node_ip}"
    ssh k8s@${node_ip} "mkdir -p ~/.kube"
    scp kubectl.kubeconfig k8s@${node_ip}:~/.kube/config
    ssh root@${node_ip} "mkdir -p ~/.kube"
    scp kubectl.kubeconfig root@${node_ip}:~/.kube/config
  done

# 下载和分发 etcd 二进制文件
# curl -OL https://github.com/coreos/etcd/releases/download/v3.3.7/etcd-v3.3.7-linux-amd64.tar.gz
cp /vagrant/etcd-v3.3.7-linux-amd64.tar.gz .
tar -zxf etcd-v3.3.7-linux-amd64.tar.gz
source /opt/k8s/bin/environment.sh
for node_ip in ${NODE_IPS[@]}
  do
    echo "${USER}::etcd-v3.3.7-linux-amd64/etcd* >>> ${node_ip}"
    scp etcd-v3.3.7-linux-amd64/etcd* k8s@${node_ip}:/opt/k8s/bin
    ssh k8s@${node_ip} "chmod +x /opt/k8s/bin/*"
  done

# 创建 etcd 证书和私钥
cat > etcd-csr.json <<EOF
{
  "CN": "etcd",
  "hosts": [
    "127.0.0.1",
    "172.27.129.105",
    "172.27.129.111",
    "172.27.129.112"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "k8s",
      "OU": "4Paradigm"
    }
  ]
}
EOF

# 生成证书和私钥：
cfssl gencert -ca=/etc/kubernetes/cert/ca.pem \
    -ca-key=/etc/kubernetes/cert/ca-key.pem \
    -config=/etc/kubernetes/cert/ca-config.json \
    -profile=kubernetes etcd-csr.json | cfssljson -bare etcd
source /opt/k8s/bin/environment.sh
for node_ip in ${NODE_IPS[@]}
  do
    echo "etcd*.pem >>> ${node_ip}"
    ssh root@${node_ip} "mkdir -p /etc/etcd/cert && chown -R k8s /etc/etcd/cert"
    scp etcd*.pem k8s@${node_ip}:/etc/etcd/cert/
  done

# 创建 etcd 的 systemd unit 模板文件
source /opt/k8s/bin/environment.sh
cat > etcd.service.template <<EOF
[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target
Documentation=https://github.com/coreos

[Service]
User=k8s
Type=notify
WorkingDirectory=/var/lib/etcd/
ExecStart=/opt/k8s/bin/etcd \\
  --data-dir=/var/lib/etcd \\
  --name=##NODE_NAME## \\
  --cert-file=/etc/etcd/cert/etcd.pem \\
  --key-file=/etc/etcd/cert/etcd-key.pem \\
  --trusted-ca-file=/etc/kubernetes/cert/ca.pem \\
  --peer-cert-file=/etc/etcd/cert/etcd.pem \\
  --peer-key-file=/etc/etcd/cert/etcd-key.pem \\
  --peer-trusted-ca-file=/etc/kubernetes/cert/ca.pem \\
  --peer-client-cert-auth \\
  --client-cert-auth \\
  --listen-peer-urls=https://##NODE_IP##:2380 \\
  --initial-advertise-peer-urls=https://##NODE_IP##:2380 \\
  --listen-client-urls=https://##NODE_IP##:2379,http://127.0.0.1:2379 \\
  --advertise-client-urls=https://##NODE_IP##:2379 \\
  --initial-cluster-token=etcd-cluster-0 \\
  --initial-cluster=${ETCD_NODES} \\
  --initial-cluster-state=new
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# 为各节点创建和分发 etcd systemd unit 文件
source /opt/k8s/bin/environment.sh
for (( i=0; i < 3; i++ ))
  do
    sed -e "s/##NODE_NAME##/${NODE_NAMES[i]}/" -e "s/##NODE_IP##/${NODE_IPS[i]}/" etcd.service.template > etcd-${NODE_IPS[i]}.service 
  done
ls *.service

source /opt/k8s/bin/environment.sh
for node_ip in ${NODE_IPS[@]}
  do
    echo "etcd-${node_ip}.service >>> ${node_ip}"
    ssh root@${node_ip} "mkdir -p /var/lib/etcd && chown -R k8s /var/lib/etcd" 
    scp etcd-${node_ip}.service root@${node_ip}:/etc/systemd/system/etcd.service
  done

# 启动 etcd 服务
source /opt/k8s/bin/environment.sh
for node_ip in ${NODE_IPS[@]}
  do
    echo "start etcd service >>> ${node_ip}"
    ssh root@${node_ip} "systemctl daemon-reload && systemctl enable etcd && systemctl restart etcd"
  done

# 检查启动结果
source /opt/k8s/bin/environment.sh
for node_ip in ${NODE_IPS[@]}
  do
    echo "check etcd status >>> ${node_ip}"
    ssh k8s@${node_ip} "systemctl status etcd|grep Active"
  done
# journalctl -u etcd

# 验证服务状态
source /opt/k8s/bin/environment.sh
for node_ip in ${NODE_IPS[@]}
  do
    echo "check etcd health >>> ${node_ip}"
    ETCDCTL_API=3 /opt/k8s/bin/etcdctl \
    --endpoints=https://${node_ip}:2379 \
    --cacert=/etc/kubernetes/cert/ca.pem \
    --cert=/etc/etcd/cert/etcd.pem \
    --key=/etc/etcd/cert/etcd-key.pem endpoint health
  done
