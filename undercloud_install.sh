#!/bin/bash
# Refer to below link for detailed install steps
# http://tripleo-docs.readthedocs.io/en/latest/installation/installation.html

usage()
{
    echo "Usage: $0 "
    echo -e "\t -u <proxy_user> -p <proxy_password> -l <proxy_url> -s <slot_num> "
    echo -e "\t [-r <openstack_release default is ocata>]"
    echo -e "\t [-i <ip address prefix, eg -i 192.168.25>]"
    echo -e "eg $0 -u user1 -p 123456 -l proxy.com:8080 -s 4"
    echo -e "\n"
    exit 0
}

while getopts "u:p:l:s:r:i:" arg
do
    case $arg in
        u)
            proxy_user="$OPTARG"
            ;;
        p)
            proxy_password="$OPTARG"
            ;;
        l)
            proxy_url="$OPTARG"
            ;;
        s)
            slot="$OPTARG"
            ;;
        r)
            release="$OPTARG"
            ;;
        i)
            ip_prefix="$OPTARG"
            ;;
        ?)
            echo "unknow argument"
            usage
            ;;
     esac
done

release=${release:-'ocata'}
ip_prefix=${ip_prefix:-'192.168.24'}

case $slot in
    1)
        pxe_interface="enp4s0f1"
        ipmi_interface="enp4s0f1"
        ;;
    2)
        pxe_interface="enp4s0f1"
        ipmi_interface="enp4s0f1"
        ;;
    3)
        pxe_interface="enp4s0f1"
        ipmi_interface="enp4s0f1"
        ;;
    4)
        pxe_interface="enp4s0f1"
        ipmi_interface="enp4s0f1"
        ;;
    ?)
        echo "unknown slot num"
        exit 1
        ;;
esac

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

# add http_proxy in yum.conf
crudini --set /etc/yum.conf main proxy $http_proxy
crudini --get /etc/yum.conf main proxy
# disable sslVerify in yum.conf
crudini --set /etc/yum.conf main sslVerify false
crudini --get /etc/yum.conf main sslVerify
unset http_proxy
unset https_proxy

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
hostname="undercloud-slot$slot"
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
crudini --set /home/stack/undercloud.conf DEFAULT local_ip ${ip_prefix}.1/24
crudini --set /home/stack/undercloud.conf DEFAULT undercloud_public_vip  ${ip_prefix}.10
crudini --set /home/stack/undercloud.conf DEFAULT undercloud_admin_vip ${ip_prefix}.11
crudini --set /home/stack/undercloud.conf DEFAULT local_interface $pxe_interface
crudini --set /home/stack/undercloud.conf DEFAULT masquerade_network ${ip_prefix}.0/24
crudini --set /home/stack/undercloud.conf DEFAULT dhcp_start ${ip_prefix}.20
crudini --set /home/stack/undercloud.conf DEFAULT dhcp_end ${ip_prefix}.120
crudini --set /home/stack/undercloud.conf DEFAULT network_cidr ${ip_prefix}.0/24
crudini --set /home/stack/undercloud.conf DEFAULT network_gateway ${ip_prefix}.1
crudini --set /home/stack/undercloud.conf DEFAULT discovery_iprange ${ip_prefix}.150,${ip_prefix}.180

# add ip address for ipmi interface
sudo ip addr add 190.9.4.61/16 dev $ipmi_interface

# switch to stack user
su - stack

# comment out undercloud deploy cmd since 
# python-tripleoclient may fail

# openstack undercloud install
