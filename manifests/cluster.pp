#
# Suit to your needs
#
$hosts = "10.10.10.90 node1\n10.10.10.91 node2\n"
$nameserver = "10.10.10.1"
$sernet_creds = file("/vagrant/files/sernet_creds")
$sernet_repo = "download.sernet.de/packages/samba/4.1/centos/6"
$ctdb_rpm_url = "http://download.sernet.de/pub/ctdb/1.0.114/rhel/6/x86_64/ctdb-1.0.114.9-1.x86_64.rpm"
$gpfs_version = "3.5.0"
$gpfs_patchlevel = "15"

$smb_conf = "[Global]
        clustering = yes
        netbios name = Samba Cluster
        workgroup = CLUSTER
        security = user
        gpfs:dfreequota = yes
        gpfs:hsm = yes
        gpfs:leases = yes
        gpfs:prealloc = yes
        gpfs:sharemodes = yes
        gpfs:winattr = yes
        gpfs:ftruncate = no
        nfs4:acedup = merge
        nfs4:chown = yes
        nfs4:mode = simple
        ea support = yes

[test]
        path = /gpfs/test
        writeable = yes
        vfs objects = fruit streams_xattr gpfs
"

$ctdb_conf = "CTDB_RECOVERY_LOCK=/gpfs/ctdb.lock
CTDB_NODES=/etc/ctdb/nodes
CTDB_PUBLIC_ADDRESSES=/etc/ctdb/public_addresses
CTDB_PUBLIC_INTERFACE=eth1
"

$ctdb_nodes = "10.10.10.90
10.10.10.91
"

$ctdb_addresses = "10.10.10.92
10.10.10.93
"

group { 'puppet': ensure => 'present' }

# http://grokbase.com/t/gg/puppet-users/14a715pdsq/annoying-allow-virtual-parameter-warning
Package { allow_virtual => true } 

# missing packages for compiling Samba:
# git emacs-nox python-devel libacl-devel openldap-devel

class packages {
  $buildtools = ["automake", "autoconf", "make", "kernel-headers", "kernel-devel", "gcc", "gcc-c++", "rpmdevtools", "ksh", "rsh", "libaio", "emacs-nox", "python-devel", "libacl-devel", "openldap-devel"]
  package { $buildtools:
    ensure => "installed"
  }
}

class samba {
  require packages

  yumrepo { "sernet-samba":
    baseurl=> "https://$sernet_creds@$sernet_repo/",
    gpgcheck=> "1",
    gpgkey=> "https://$sernet_creds@$sernet_repo/repodata/repomd.xml.key",
    enabled=> "1",
  } ~>
  exec { "yum-update":
    command => "/usr/bin/yum clean all && /usr/bin/yum check-update",
    refreshonly => true,
    returns => [0, 100]
  }

  package { "sernet-samba":
    ensure => present,
    require => Yumrepo["sernet-samba"]
  }

  package { "ctdb":
    source => "$ctdb_rpm_url",
    ensure => "installed",
    provider => "rpm"
  }

  file { "smb_conf":
    path => "/etc/samba/smb.conf",
    content => $smb_conf,
    require => Package["sernet-samba"]
  }
}

class gpfs {
  require packages

  package { "compat-libstdc++-33":
    ensure => "installed"
  }

  package { "gpfs.base":
    source => "file:///vagrant/files/gpfs.base-$gpfs_version-0.x86_64.rpm",
    ensure => "installed",
    require => Package[$buildtools],
    provider => "rpm"
  }

  exec { "update-gpfs":
    command => "/bin/rpm -U /vagrant/files/gpfs.base-$gpfs_version-$gpfs_patchlevel.x86_64.update.rpm",
    subscribe => Package["gpfs.base"],
    refreshonly => true
  }

  package { "gpfs.docs":
    source => "file:///vagrant/files/gpfs.docs-$gpfs_version-$gpfs_patchlevel.noarch.rpm",
    ensure => "installed",
    require => Package["gpfs.base"],
    provider => "rpm"
  }

  package { "gpfs.gpl":
    source => "file:///vagrant/files/gpfs.gpl-$gpfs_version-$gpfs_patchlevel.noarch.rpm",
    ensure => "installed",
    require => Package["gpfs.base"],
    provider => "rpm"
  }

  package { "gpfs.msg.en_US":
    source => "file:///vagrant/files/gpfs.msg.en_US-$gpfs_version-$gpfs_patchlevel.noarch.rpm",
    ensure => "installed",
    require => Package["gpfs.base"],
    provider => "rpm"
  }
}

class gpfs-km {
  require gpfs

  exec { "build-kernel-module":
    cwd => "/usr/lpp/mmfs/src",
    command => "/usr/bin/make LINUX_DISTRIBUTION=REDHAT_AS_LINUX clean Autoconfig World rpm",
    unless => "/usr/bin/test -f /rpmbuild/RPMS/x86_64/gpfs.gplbin-2.6.32-504.1.3.el6.x86_64-$gpfs_version-$gpfs_patchlevel.x86_64.rpm",
  }

  package { "gpfs.gplbin-2.6.32-504.1.3.el6.x86_64-$gpfs_version-$gpfs_patchlevel.x86_64":
    source => "file:///rpmbuild/RPMS/x86_64/gpfs.gplbin-2.6.32-504.1.3.el6.x86_64-$gpfs_version-$gpfs_patchlevel.x86_64.rpm",
    ensure => "installed",
    require => Exec["build-kernel-module"],
    provider => "rpm"
  }
}

class network {
    file { "/etc/hosts":
      content => "$hosts",
    }

    file { "/etc/resolv.conf":
      content => "nameserver $nameserver",
    }
}

class ssh {
  require network

  file { "/root/.ssh":
    ensure => "directory"
  }

  file { "ssh-key":
    path => "/root/.ssh/id_rsa",
    ensure => "present",
    source => "/vagrant/files/id_rsa",
    require => File["/root/.ssh"],
  } ~>
  exec { "authorized-keys":
    command => "/bin/cat /vagrant/files/id_rsa.pub >> /root/.ssh/authorized_keys",
    refreshonly => true,
  }

  file { "ssh_config":
    path => "/etc/ssh/ssh_config",
    content => "StrictHostKeyChecking=no",
    ensure => "present",
    owner => "root",
    group => "root"
  }
}

class cluster {
  require gpfs-km
  require ssh

  file { "/gpfs":
    ensure => "directory"
  }

  file { "diskdef.txt":
    path => "/root/diskdef.txt",
    content => "/dev/sdb:node1,node2\n"
  }

  exec { "mmcrcluster":
    command => "/usr/lpp/mmfs/bin/mmcrcluster -N node1:quorum,node2:quorum -p node1 -s node2 -r /usr/bin/ssh -R /usr/bin/scp",
    onlyif => "/usr/bin/test \$(hostname) = node1",
    unless => "/usr/lpp/mmfs/bin/mmgetstate -N node1"
  } ~>
  exec { "mmchlicense":
    command => "/usr/lpp/mmfs/bin/mmchlicense server --accept -N node1,node2",
    refreshonly => true
  } ~>
  exec { "mmstartup":
    command => "/usr/lpp/mmfs/bin/mmstartup -a",
    refreshonly => true
  } ~>
  exec { "mmcrnsd":
    command => "/usr/lpp/mmfs/bin/mmcrnsd -F /root/diskdef.txt",
    refreshonly => true,
    require => File["/root/diskdef.txt"]
  } ~>
  exec { "mmcrfs":
    command => "/usr/lpp/mmfs/bin/mmcrfs gpfs1 -F /root/diskdef.txt -A yes -T /gpfs",
    refreshonly => true,
    require => File["/gpfs"]
  } ~>
  exec { "mmmount":
    command => "/usr/lpp/mmfs/bin/mmmount /gpfs -a",
    refreshonly => true
  }
}

class ctdb {
  require samba

  file { "ctdb_conf":
    path => "/etc/sysconfig/ctdb",
    content => $ctdb_conf
  }

  file { "ctdb_nodes":
    path => "/etc/ctdb/nodes",
    content => $ctdb_nodes
  }

  file { "ctdb_addresses":
    path => "/etc/ctdb/public_addresses",
    content => $ctdb_addresses
  }
}

include packages
include network
include ssh
include samba
include gpfs
include gpfs-km
include cluster
include ctdb
