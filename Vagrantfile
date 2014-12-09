# Suit to your needs
bridge_if ||= 'en1: WLAN (AirPort)'
node1_ip ||= '10.10.10.90'
node2_ip ||= '10.10.10.91'
ip_netmask ||= '255.255.255.0'
vm_memory ||= '1024'

# Vagrantfile API/syntax version. Don't touch unless you know what you're doing!
VAGRANTFILE_API_VERSION = "2"

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  config.vm.box = "puppet/centos-6.6"

  # node2 must be brought up before node1
  config.vm.define "node2" do |node2|
    node2.vm.hostname = "node2"
    node2.vm.network "public_network", bridge: bridge_if, ip: node2_ip, netmask: ip_netmask
    node2.vm.provider "virtualbox" do |vb|
      vb.customize ["modifyvm", :id , "--memory", vm_memory]
      if !File.exist?('gpfs.vdi')
        vb.customize ['createhd', '--filename', 'gpfs.vdi', '--size', 1024, '--variant', 'fixed']
        vb.customize ['modifyhd', 'gpfs.vdi', '--type', 'shareable']
      end
      vb.customize ['storageattach', :id, '--storagectl', 'SATA Controller', '--port', 1, '--device', 0, '--type', 'hdd', '--medium', 'gpfs.vdi']
    end

    node2.vm.provision "puppet" do |puppet|
      puppet.manifests_path = "manifests"
      puppet.manifest_file  = "cluster.pp"
    end
  end

  config.vm.define "node1" do |node1|
    node1.vm.hostname = "node1"
    node1.vm.network "public_network", bridge: bridge_if, ip: node1_ip, netmask: ip_netmask
    node1.vm.provider "virtualbox" do |vb|
      vb.customize ["modifyvm", :id, "--memory", vm_memory]
      vb.customize ['storageattach', :id, '--storagectl', 'SATA Controller', '--port', 1, '--device', 0, '--type', 'hdd', '--medium', 'gpfs.vdi']
    end

    node1.vm.provision "puppet" do |puppet|
      puppet.manifests_path = "manifests"
      puppet.manifest_file  = "cluster.pp"
    end
  end
end
