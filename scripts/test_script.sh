#!/usr/bin/env bash

# set the Keystone v3 environment for admin access
export OS_USERNAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export NOVA_VERSION=1.1
export OS_PROJECT_NAME=admin
export OS_PASSWORD=$(sudo hiera admin_password)
export OS_NO_CACHE=True
export COMPUTE_API_VERSION=1.1
export no_proxy=,192.168.122.150,172.16.0.250
export OS_CLOUDNAME=overcloud
export OS_AUTH_URL=https://192.168.122.150:13000/v3
export OS_IDENTITY_API_VERSION=3
export OS_AUTH_TYPE=password
export PYTHONWARNINGS="ignore:Certificate has no, ignore:A true SSLContext object is not available"

# Create the external network
openstack network create external --external --provider-network-type flat --provider-physical-network datacentre
openstack subnet create --network external --gateway 192.168.122.1 --allocation-pool start=192.168.122.151,end=192.168.122.200 --no-dhcp --subnet-range 192.168.122.0/24 external

# Add a Cirros image
curl http://download.cirros-cloud.net/0.3.4/cirros-0.3.4-x86_64-disk.img | openstack image create --disk-format qcow2 --container-format bare  --public cirros-0.3.4-x86_64

# Create a flavor
openstack flavor create m1.tiny --id auto --ram 512 --disk 1 --vcpus 1
openstack flavor list

# create the project and add the user to it
openstack project create labproject --domain LAB
openstack project list --domain LAB
openstack user list --domain LAB
openstack role add --user test-user --user-domain LAB --project labproject --project-domain LAB _member_

# set the Keystone v3 environment for the LDAP user
export OS_USERNAME=test-user
export NOVA_VERSION=1.1
export OS_PROJECT_NAME=labproject
export OS_PASSWORD=test
export OS_NO_CACHE=True
export COMPUTE_API_VERSION=1.1
export no_proxy=,192.168.122.150,172.16.0.250,192.168.122.150,172.16.0.250
export OS_CLOUDNAME=overcloud
export OS_AUTH_URL=https://192.168.122.150:13000/v3
export OS_AUTH_TYPE=password
export PYTHONWARNINGS="ignore:Certificate has no, ignore:A true SSLContext object is not available"
export OS_IDENTITY_API_VERSION=3
export OS_USER_DOMAIN_NAME=LAB
export OS_PROJECT_DOMAIN_NAME=LAB

# As the project user, create a network, subnet, and router
openstack network create test-net
openstack subnet create --network test-net --gateway 192.168.123.254 --allocation-pool start=192.168.123.1,end=192.168.123.253 --dns-nameserver 10.12.50.1  --subnet-range 192.168.123.0/24 test-subnet
openstack router create test-router
openstack router set --external-gateway external test-router
openstack router add subnet test-router test-subnet

# Allow SSH and ICMP
openstack security group rule list default
openstack security group rule create default --protocol tcp --dst-port 22:22 --remote-ip 0.0.0.0/0 
openstack security group rule create default --protocol icmp --remote-ip 0.0.0.0/0

# Create a keypair and floating IP
openstack keypair create --public-key ~/.ssh/id_rsa.pub test-user
openstack floating ip create external
NETID=$(openstack network show test-net | awk ' / id/ { print $4 } '); echo $NETID

# Boot an instance
openstack server create --image cirros-0.3.4-x86_64 --flavor m1.tiny --key-name test-user --nic net-id=$NETID --security-group default test-server
sleep 10

# Assign a floating IP to the instance and test
FLOATIP=$(openstack floating ip list | awk ' /192.168/ { print $4 } '); echo $FLOATIP
openstack server add floating ip test-server $FLOATIP
ping -c3 $FLOATIP
ssh -o StrictHostKeyChecking=no cirros@$FLOATIP uptime
