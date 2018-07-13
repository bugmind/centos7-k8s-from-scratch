# -*- mode: ruby -*-
# vi: set ft=ruby :

NUM_WORKERS = 2

Vagrant.configure("2") do |config|
 
  (1..NUM_WORKERS).each do |n|
    config.vm.define "kube-node#{n+1}" do |worker|
      
      worker.vm.provider 'virtualbox' do |vb|
        vb.memory = '2048'
      end

      worker.vm.box = 'centos/7'
      worker.vm.box_check_update = false

      worker.vm.hostname = "kube-node#{n+1}"
      worker.vm.network 'private_network', ip: "172.27.129.11#{n}"

      worker.vm.provision :shell, path: "bootstrap.sh"
    end
  end

  config.vm.define 'kube-node1' do |master|

    master.vm.provider 'virtualbox' do |vb|
      vb.memory = '2048'
      vb.cpus = 2
    end

    master.vm.box = 'centos/7'
    master.vm.box_check_update = false

    master.vm.hostname = 'kube-node1'
    master.vm.network 'private_network', ip: '172.27.129.105'

    master.vm.provision :shell, path: "bootstrap.sh"
    master.vm.provision :shell, path: "init_etcd.sh"
    master.vm.provision :shell, path: "init_flanneld.sh"
    master.vm.provision :shell, path: "init_master.sh"
    master.vm.provision :shell, path: "init_worker.sh"
    master.vm.provision :shell, path: "init_addons.sh"
  end

end
