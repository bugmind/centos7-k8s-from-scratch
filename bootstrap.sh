sudo -i

# 修改每台机器的 /etc/hosts 文件，添加主机名和 IP 的对应关系：
echo '172.27.129.105	kube-node1	kube-node1' >> /etc/hosts
echo '172.27.129.111	kube-node2	kube-node2' >> /etc/hosts
echo '172.27.129.112	kube-node3	kube-node3' >> /etc/hosts

# 在每台机器上添加 k8s 账户，可以无密码 sudo：
useradd -m k8s
usermod --password $(echo k8s | openssl passwd -1 -stdin) k8s
sed --in-place 's/^#\s*\(%wheel\s\+ALL=(ALL)\s\+NOPASSWD:\s\+ALL\)/\1/' /etc/sudoers
gpasswd -a k8s wheel

# 在每台机器上添加 docker 账户，将 k8s 账户添加到 docker 组中，同时配置 dockerd 参数：
useradd -m docker
gpasswd -a k8s docker
mkdir -p  /etc/docker/
cat <<EOF >/etc/docker/daemon.json
{
    "registry-mirrors": ["https://hub-mirror.c.163.com", "https://docker.mirrors.ustc.edu.cn"],
    "max-concurrent-downloads": 20
}
EOF

# 在每台机器上添加环境变量：
sh -c "echo 'PATH=/opt/k8s/bin:$PATH:$HOME/bin:$JAVA_HOME/bin' >>/root/.bashrc"
echo 'PATH=/opt/k8s/bin:$PATH:$HOME/bin:$JAVA_HOME/bin' >>~/.bashrc

# 在每台机器上安装依赖包：
yum install -y epel-release
yum install -y conntrack ipvsadm ipset jq sysstat curl iptables

# 在每台机器上关闭防火墙：
systemctl stop firewalld
systemctl disable firewalld
iptables -F && iptables -X && iptables -F -t nat && iptables -X -t nat
iptables -P FORWARD ACCEPT

# 在每台机器上创建目录：
mkdir -p /opt/k8s/bin && chown -R k8s /opt/k8s
mkdir -p /etc/kubernetes/cert && chown -R k8s /etc/kubernetes
mkdir -p /etc/etcd/cert && chown -R k8s /etc/etcd/cert
mkdir -p /var/lib/etcd && chown -R k8s /etc/etcd/cert

# 如果开启了 swap 分区，kubelet 会启动失败(可以通过将参数 --fail-swap-on 设置为 false 来忽略 swap on)，故需要在每台机器上关闭 swap 分区：
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# 关闭 SELinux，否则后续 K8S 挂载目录时可能报错 Permission denied：
setenforce 0
sed -i '/SELINUX=enforcing/c\SELINUX=disabled' /etc/selinux/config

# 设置系统参数
cat > /etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
vm.swappiness=0
vm.overcommit_memory=1
vm.panic_on_oom=0
EOF
sysctl -p /etc/sysctl.d/kubernetes.conf

# 加载内核模块
modprobe br_netfilter
modprobe ip_vs

# 设置系统时区
# 调整系统 TimeZone
timedatectl set-timezone Asia/Shanghai
# 将当前的 UTC 时间写入硬件时钟
timedatectl set-local-rtc 0
# 重启依赖于系统时间的服务
systemctl restart rsyslog 
systemctl restart crond

# ssh-copy-id Permission denied 
sed -i '/PasswordAuthentication no/c\PasswordAuthentication yes' /etc/ssh/sshd_config
systemctl restart sshd
