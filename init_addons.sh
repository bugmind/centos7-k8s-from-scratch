sudo -i
cd /opt/k8s

# 部署 coredns 插件
tar -zxf kubernetes/kubernetes-src.tar.gz -C kubernetes
cp kubernetes/cluster/addons/dns/coredns.yaml.base kubernetes/cluster/addons/dns/coredns.yaml
sed -i 's/__PILLAR__DNS__DOMAIN__/cluster.local./g' kubernetes/cluster/addons/dns/coredns.yaml
sed -i 's/__PILLAR__DNS__SERVER__/10.254.0.2/g' kubernetes/cluster/addons/dns/coredns.yaml
kubectl create -f kubernetes/cluster/addons/dns/coredns.yaml

# 部署 dashboard 插件
sed -i 's/k8s.gcr.io/siriuszg/g' kubernetes/cluster/addons/dashboard/dashboard-controller.yaml
echo '  type: NodePort' >> kubernetes/cluster/addons/dashboard/dashboard-service.yaml
kubectl create -f kubernetes/cluster/addons/dashboard/

kubectl create sa dashboard-admin -n kube-system
kubectl create clusterrolebinding dashboard-admin --clusterrole=cluster-admin --serviceaccount=kube-system:dashboard-admin

# 获取访问dashboard的token  和  创建config文件
ADMIN_SECRET=$(kubectl get secrets -n kube-system | grep dashboard-admin | awk '{print $1}')
DASHBOARD_LOGIN_TOKEN=$(kubectl describe secret -n kube-system ${ADMIN_SECRET} | grep -E '^token' | awk '{print $2}')
echo ${DASHBOARD_LOGIN_TOKEN}

source /opt/k8s/bin/environment.sh
# 设置集群参数
kubectl config set-cluster kubernetes \
  --certificate-authority=/etc/kubernetes/cert/ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=dashboard.kubeconfig

# 设置客户端认证参数，使用上面创建的 Token
kubectl config set-credentials dashboard_user \
  --token=${DASHBOARD_LOGIN_TOKEN} \
  --kubeconfig=dashboard.kubeconfig

# 设置上下文参数
kubectl config set-context default \
  --cluster=kubernetes \
  --user=dashboard_user \
  --kubeconfig=dashboard.kubeconfig

# 设置默认上下文
kubectl config use-context default --kubeconfig=dashboard.kubeconfig

# 部署 heapster 插件
#curl -OL https://github.com/kubernetes/heapster/archive/v1.5.3.tar.gz
cp /vagrant/v1.5.3.tar.gz .
tar -zxf v1.5.3.tar.gz

sed -i 's/gcr.io\/google_containers\/heapster-grafana-amd64:v4.4.3/wanghkkk\/heapster-grafana-amd64-v4.4.3:v4.4.3/g' heapster-1.5.3/deploy/kube-config/influxdb/grafana.yaml
sed -i 's/# type: NodePort/type: NodePort/g' heapster-1.5.3/deploy/kube-config/influxdb/grafana.yaml

sed -i 's/gcr.io\/google_containers\/heapster-amd64:v1.5.3/fishchen\/heapster-amd64:v1.5.3/g' heapster-1.5.3/deploy/kube-config/influxdb/heapster.yaml
sed -i 's/kubernetes.default/kubernetes.default?kubeletHttps=true\&kubeletPort=10250/g' heapster-1.5.3/deploy/kube-config/influxdb/heapster.yaml

sed -i 's/gcr.io\/google_containers/fishchen/g' heapster-1.5.3/deploy/kube-config/influxdb/influxdb.yaml

kubectl create -f heapster-1.5.3/deploy/kube-config/influxdb/

cat >> heapster-1.5.3/deploy/kube-config/rbac/heapster-rbac.yaml <<EOF
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: heapster-kubelet-api
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kubelet-api-admin
subjects:
- kind: ServiceAccount
  name: heapster
  namespace: kube-system
EOF
kubectl create -f heapster-1.5.3/deploy/kube-config/rbac/
