Vagrant.configure("2") do |config|
  
  config.vm.box = "centos/7"
  
  config.vm.network "private_network", ip: "10.18.6.60"
  
  config.vm.provision "shell", path: "setup/development.sh"
end
