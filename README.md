## repo来源
这个repo的内容都来自[follow-me-install-kubernetes-cluster](https://github.com/opsnull/follow-me-install-kubernetes-cluster.git)，从零纯手工搭建kubernetes集群的教程，感谢@opsnull。我只是把里面的内容整理成一键脚本，方便大家快速部署和使用。

## precondition
使用`vagrant + virtualbox`搭建，你的host机器需要安装[vagrant](https://www.vagrantup.com/)， virtualbox， kubectl

## usage
1. 下载repo内容
   ```
   $ git clone https://github.com/yaxu666/centos7-k8s-from-scratch.git
   ```

2. 下载需要的软件包，注意你需要保证着里面的所有软件都完整下载，尤其最后k8s的client和server两个包
	 ```
	 $ chmod +x download.sh && ./download.sh
	 ```

3. 启动VMs，等待自动完成注意最后是不是成功执行
   ```
   $ vagrant up
   ```

4. 拷贝kubeconfig文件和查看dashboard(root密码默认是`vagrant`)
   ```
   $ scp root@172.27.129.105:/opt/k8s/dashboard.kubeconfig .
   $ kubectl get svc -n kube-system --kubeconfig dashboard.kubeconfig|grep dashboard

     kubernetes-dashboard   NodePort    10.254.49.215    <none>        443:8994/TCP    5m
   ```

5. 访问dashboard，查看集群状态
	 浏览器访问`https://172.27.129.105:8994`，（端口即上一步查看到的servie映射端口)，选用dashboard.kubeconfig文件登陆

## 其他
~目前还存在一点问题，在对pod使用`kubectl logs`和`kubectl exec`两个命令时会出现[问题](https://github.com/opsnull/follow-me-install-kubernetes-cluster/issues/278)，有兴趣弄明白的大哥分享一下~
原因在此：[kubernetes/kubernetes#65939](https://github.com/kubernetes/kubernetes/issues/65939)