#!/bin/bash

# configure network proxy
proxy_user=""
proxy_password=""
proxy_url=""

http_proxy="http://$proxy_user:$proxy_password@$proxy_url"
https_proxy="https://$proxy_user:$proxy_password@$proxy_url"

export http_proxy=$http_proxy
export https_proxy=$https_proxy

# yum install is not available at this stage,
# use curl to download crudini package which
# will be used to configure yum proxy later

crudini_package_name='crudini-0.9-1.el7.noarch.rpm'
crudini_url="http://dl.fedoraproject.org/pub/epel/7/x86_64/c/$crudini_package_name"
grep -q 'insecure' ~/.curlrc || echo "insecure" >> ~/.curlrc
curl -o ./$crudini_package_name $crudini_url
rpm -ivh ./$crudini_package_name
unset http_proxy
unset https_proxy

# add http_proxy in yum.conf
crudini --set /etc/yum.conf main proxy $http_proxy
crudini --get /etc/yum.conf main proxy
# disable sslVerify in yum.conf
crudini --set /etc/yum.conf main sslVerify false
crudini --get /etc/yum.conf main sslVerify

release=ocata

if [ $release = ocata ]; then
    delorean_repo="https://trunk.rdoproject.org/centos7-ocata/current/delorean.repo"
    delorean_deps_repo="https://trunk.rdoproject.org/centos7-ocata/delorean-deps.repo"
elif [ $release = newton ];then
    delorean_repo="https://trunk.rdoproject.org/centos7-newton/current/delorean.repo"
    delorean_deps_repo="https://trunk.rdoproject.org/centos7-newton/delorean-deps.repo"
else
    echo "no release specified, existing"
    exit
fi

# create a non-root user
sudo useradd stack
echo "redhat" | passwd stack --stdin

sudo_conf='stack ALL=(root) NOPASSWD:ALL'
sudo_conf_file='/etc/sudoers.d/stack'
grep -q $sudo_conf $sudo_conf_file || echo $sudo_conf | sudo tee -a $sudo_conf_file
sudo chmod 0440 /etc/sudoers.d/stack

# match FQDN hostname with $HOSTNAME environment variable
hostname="undercloud"
host_entry="127.0.0.1 $hostname $hostname"
host_entry_file="/etc/hosts"
sudo hostnamectl set-hostname $hostname
sudo hostnamectl set-hostname --transient $hostname
grep -q $host_entry $host_entry_file || echo $host_entry >> $host_entry_file

# download necessary delorean repos
curl -L -o /etc/yum.repos.d/delorean-${release}.repo $delorean_repo
curl -L -o /etc/yum.repos.d/delorean-deps-${release}.repo $delorean_deps_repo

yum install -y yun-plugin-priorities

# python-tripleoclient package installation may
# fail due to slow network connections, try to
# execute it several times or manually install
# the missing packages.
yum install -y python-tripleoclient

undercloud_conf_file='/home/stack/undercloud.conf'
if [ ! -f $undercloud_conf_file ]; then
    cp /usr/share/instack-undercloud/undercloud.conf.sample /home/stack/undercloud.conf
fi

# add undercloud configurations in undercloud.conf
pxe_interface="enp4s0f1"

crudini --set /home/stack/undercloud.conf DEFAULT local_ip 192.168.24.1/24
crudini --set /home/stack/undercloud.conf DEFAULT undercloud_public_vip  192.168.24.10
crudini --set /home/stack/undercloud.conf DEFAULT undercloud_admin_vip 192.168.24.11
crudini --set /home/stack/undercloud.conf DEFAULT local_interface $pxe_interface
crudini --set /home/stack/undercloud.conf DEFAULT masquerade_network 192.168.24.0/24
crudini --set /home/stack/undercloud.conf DEFAULT dhcp_start 192.168.24.20
crudini --set /home/stack/undercloud.conf DEFAULT dhcp_end 192.168.24.120
crudini --set /home/stack/undercloud.conf DEFAULT network_cidr 192.168.24.0/24
crudini --set /home/stack/undercloud.conf DEFAULT network_gateway 192.168.24.1
crudini --set /home/stack/undercloud.conf DEFAULT discovery_iprange 192.168.24.150,192.168.24.180

# switch to stack user
su - stack

# comment out undercloud deploy cmd since 
# python-tripleoclient may fail

# openstack undercloud install
