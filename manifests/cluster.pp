#
# Suit to your needs
#
$hosts = "10.10.10.90 node1\n10.10.10.91 node2\n"
$nameserver = "10.10.10.1"
$sernet_creds = file("/vagrant/files/sernet_creds")
# $sernet_repo = "download.sernet.de/packages/samba/4.1/centos/6"
$sernet_repo = "download.sernet.de/packages/samba/.staging/4.2/centos/6/"

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

$ctdb_addresses = "10.10.10.92/24 eth1
10.10.10.93/24 eth1
"

$sernet_samba_defaults = "SAMBA_START_MODE=classic
SAMBA_RESTART_ON_UPDATE=no
NMBD_EXTRA_OPTS=
WINBINDD_EXTRA_OPTS=
SMBD_EXTRA_OPTS=
SAMBA_EXTRA_OPTS=
SAMBA_IGNORE_NSUPDATE_G=no"

$selinux_conf = "SELINUX=permissive
SELINUXTYPE=targeted"

group { 'puppet': ensure => 'present' }

# http://grokbase.com/t/gg/puppet-users/14a715pdsq/annoying-allow-virtual-parameter-warning
Package { allow_virtual => true } 

class base {
  file { "selinux":
    path => "/etc/sysconfig/selinux",
    content => $selinux_conf
  } ~>
  exec { "setenforce":
    command => "/usr/sbin/setenforce 0",
    refreshonly => true
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

class packages {
  require base

  yumrepo { "sernet-samba":
    baseurl=> "https://$sernet_creds@$sernet_repo/",
    gpgcheck=> "0",
    gpgkey=> "https://$sernet_creds@$sernet_repo/repodata/repomd.xml.key",
    enabled=> "1",
  } ~>
  exec { "yum-update":
    command => "/usr/bin/yum clean all && /usr/bin/yum check-update",
    refreshonly => true,
    returns => [0, 100]
  } ~>
  exec { "packages":
    command => "/usr/bin/yum -qy install automake autoconf make kernel-headers kernel-devel gcc gcc-c++ compat-libstdc++-33 rpmdevtools ksh rsh libaio emacs-nox python-devel libacl-devel openldap-devel git sernet-samba sernet-samba-ctdb",
    refreshonly => true
  } ~>
  package { "sernet-samba":
    ensure => present,
  } ~>
  package { "sernet-samba-ctdb":
    ensure => present,
  }
}

class gpfs {
  require packages

  package { "gpfs.base":
    source => "file:///vagrant/files/gpfs.base-$gpfs_version-0.x86_64.rpm",
    ensure => "installed",
    provider => "rpm"
  } ~>
  exec { "update-gpfs":
    command => "/bin/rpm -U /vagrant/files/gpfs.base-$gpfs_version-$gpfs_patchlevel.x86_64.update.rpm",
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

class cluster {
  require gpfs-km
  require ssh

  file { "/gpfs":
    ensure => "directory",
    mode => 0755
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
  require packages
  require cluster

  exec { "mmstartup2":
    command => "/usr/lpp/mmfs/bin/mmstartup -a",
  } ~>
  exec { "mmmount2":
    command => "/usr/lpp/mmfs/bin/mmmount /gpfs -a",
    refreshonly => true
  }

  file { "ctdb_conf":
    path => "/etc/sysconfig/ctdb",
    content => $ctdb_conf,
    require => Package["sernet-samba-ctdb"]
  }

  file { "ctdb_nodes":
    path => "/etc/ctdb/nodes",
    content => $ctdb_nodes,
    require => Package["sernet-samba-ctdb"]
  }

  file { "ctdb_addresses":
    path => "/etc/ctdb/public_addresses",
    content => $ctdb_addresses,
    require => Package["sernet-samba-ctdb"]
  }
}

class samba {
  require packages
  require ctdb

  file { "/gpfs/test":
    ensure => "directory",
    mode => 0777
  }

  file { "sernet_samba_defaults":
    path => "/etc/default/sernet-samba",
    content => $sernet_samba_defaults,
    require => Package["sernet-samba"]
  }

  file { "smb_conf":
    path => "/etc/samba/smb.conf",
    content => $smb_conf,
    require => Package["sernet-samba"]
  }
}

class services {
  require ctdb
  require samba

  service { "sernet-samba-ctdb":
    ensure => running,
    enable => true
  }
}

include base
include packages
include network
include ssh
include samba
include gpfs
include gpfs-km
include cluster
include ctdb
include services
