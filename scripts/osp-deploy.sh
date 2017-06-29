#!/bin/bash
#
#
#   Field PM Team - Please send your feedback/bugs to gcharot@redhat.com
#



#### PLEASE SET THESE VALUES ####
RHOS_VERSION="8-director -p GA"
RHEL_VERSION=7.2

### VM Memory (GB) and vCPU count

# Undercloud
UNDERC_MEM='16384'
UNDERC_VCPU='4'

# Controllers
CTRL_MEM='8192'
CTRL_VCPU='2'

# Computes
COMPT_MEM='4096'
COMPT_VCPU='4'

# Ceph
CEPH_MEM='4096'
CEPH_VCPU='4'

# Networker
NETW_MEM='4096'
NETW_VCPU='2'

###

### Fancy colors
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
NORMAL=$(tput sgr0)


### Overcloud node's naming
CTRL_N="ctrl01 ctrl02 ctrl03"
COMPT_N="compute01 compute02"
CEPH_N="ceph01 ceph02 ceph03"
NETW_N="networker"
ALL_N="$CTRL_N $COMPT_N $CEPH_N $NETW_N"

### Misc
LIBVIRT_D="/var/lib/libvirt/"
#RHEL_IMAGE_U="http://10.12.50.1/pub/rhel-guest-image-7.3-35.x86_64.qcow2"
RHEL_IMAGE_U="http://10.12.50.1/pub/rhel-guest-image-7.2-20160302.0.x86_64.qcow2"
PKG_HYPERVISOR="screen wget libvirt qemu-kvm virt-manager virt-install libguestfs-tools libguestfs-xfs xorg-x11-apps xauth virt-viewer xorg-x11-fonts-* net-tools ntpdate mlocate sshpass squid"
PKG_UNDERCLOUD="screen wget mlocate facter python-tripleoclient libvirt libguestfs-tools openstack-utils sshpass"
WHO_I_AM="$0"

##########################################################################
#                                                                        #
#                          Common Functions                              #
#                                                                        #
##########################################################################


#
#  Print info message to stderr
#
function echoinfo() {
  printf "${GREEN}INFO:${NORMAL} %s\n" "$*" >&2;
}

#
#  Print error message to stderr
#
function echoerr() {
  printf "${RED}ERROR:${NORMAL} %s\n" "$*" >&2;
}


#
#  Print exit message & exit 1
#
function exit_on_err()
{
  echoerr "Failed to deploy - Please check the output, fix the error and restart the script"
  exit 1
}

#
# Help function
#

function help() {
  >&2 echo "Usage : osp-lab-deploy [action]

Deploy and configure virtual Red Hat Openstack Director lab

ACTIONS
========
    libvirt-deploy         Configure hypervisor and define VMs/Virtual networks
    undercloud-install     Prepare the undercloud base system for deployment
    overcloud-register     Upload overcloud images to glance and register overcloud nodes to Ironic.
    howto                  Display a quick howto
"
}

function howto()
{
  >&2 echo "
  ----- How to use osp-lab-deploy -----

Synopsis
========
    The program deploys a virtual enviroment ready to use for playing with Red Hat Director.
    Virtual enviroment is based on KVM/Libvirt - 10 VMs will be defined + 1 Provisioning Network.
    * 1 Undercloud VM
    * 3 Controllers VMs
    * 2 Compute VMs
    * 3 Ceph VMs
    * 1 Networker (Or whatever role you'd like to assign)

    Please NOTE that the script will only deploy the undercloud, other VMs are blank, though ready to deploy with Red Hat Director.

Pre-requisites
==============

    - A baremetal hypervisor with a pre-installed RHEL system, a minimum of 64GB RAM is strongly adviced.
    - Please set the CPU and Memory value for each VM flavor by editing the required variables at the begining of the script.
    - Likewise set the RHOS_VERSION and RHEL_VERSION variables.


Deploying the environment
========================

    Deployment is acheived in four steps :

    1) Hypervisor configuration and VM's definition
      - Run \"osp-lab-deploy.sh libvirt-deploy\" as root on the hypervisor
      - REBOOT your hypervisor
      - Start the undercloud VM \"virsh start undercloud\"

    2) Undercloud preparation
      - SSH into the undercloud node as root \"ssh root@undercloud\"
      - Run \" sh /tmp/osp-lab-deploy.sh undercloud-install\"
      - Reboot your system

    3) Undercloud installation
      - Once rebooted ssh back to the undercloud VM as root
      - Connect as stack user \"su - stack\"
      - Check the ~/undercloud.conf file, modify it if needed.
      - Install the undercloud as stack user \"openstack undercloud install\"

    4) Configure and register nodes
      - Run \"sh /tmp/osp-lab-deploy.sh overcloud-register\" as stack user.
      - Check everything is fine.

    You're all set ! Happy hacking !!!
"

}

#
#  Install required packages
#
function install_pakages()
{
  local pkg_list=$1

  echoinfo "---===== Installing Packages =====---"

  echoinfo "Installing rhos-release..." 

  if (rpm -q rhos-release);
    then
    echoinfo "rhos-release already installed, skipping !"
  else
    rpm -ivh http://rhos-release.virt.bos.redhat.com/repos/rhos-release/rhos-release-latest.noarch.rpm || { echoerr "Unable to install rhos-realease"; return 1; }    
    echoinfo "Configuring rhos-release..."
    rhos-release ${RHOS_VERSION} -r ${RHEL_VERSION} || { echoerr "Unable to configure rhos-realease"; return 1; } 
  fi


  echoinfo "Updating system..."
  yum update -y || { echoerr "Unable to update system"; return 1; }

  echoinfo "Installing required packages..."
  yum install $pkg_list -y || { echoerr "Unable to install required packages"; return 1; }

}



##########################################################################
#                                                                        #
#                     Hypervisor & Libvirt functions                     #
#                                                                        #
##########################################################################


#
#  Check dependencies
#
function check_requirements()
{

  # List of command dependencies
  local bin_dep="virsh virt-install qemu-img virt-resize virt-filesystems virt-customize"

  echoinfo "---===== Checking dependencies =====---"

  for cmd in $bin_dep; do
    echoinfo "Checking for $cmd..."
    $cmd --version  >/dev/null 2>&1 || { echoerr "$cmd cannot be found... Aborting"; return 1; }
  done

}


#
#  Miscellaneous system config
#
function libv_misc_sys_config()
{

  echoinfo "---===== Misc System Config =====---"


  echoinfo "Creating system user stack..."
  useradd stack

  echoinfo "Setting stack user password to redhat"
  echo "redhat" | passwd stack --stdin

  echoinfo "Configuring /etc/modprobe.d/kvm_intel.conf"
  cat << EOF > /etc/modprobe.d/kvm_intel.conf
options kvm-intel nested=1
options kvm-intel enable_shadow_vmcs=1
options kvm-intel enable_apicv=1
options kvm-intel ept=1
EOF


  echoinfo "Configuring /etc/sysctl.d/98-rp-filter.conf"
  cat << EOF > /etc/sysctl.d/98-rp-filter.conf
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.all.rp_filter = 0
EOF

  echoinfo "Applying RP filter on running interfaces"
  for i in $(sysctl -A | grep "\.rp_filter"  | cut -d" " -f1); do
   sysctl $i=0 
  done

  echoinfo "Configuring  /etc/polkit-1/localauthority/50-local.d/50-libvirt-user-stack.pkla"
  cat << EOF > /etc/polkit-1/localauthority/50-local.d/50-libvirt-user-stack.pkla
[libvirt Management Access]
Identity=unix-user:stack
Action=org.libvirt.unix.manage
ResultAny=yes
ResultInactive=yes
ResultActive=yes
EOF

  echoinfo "Creating SSH keypair"
  if [ -e ~/.ssh/id_rsa ]; then
    echoinfo "SSH keypair already exists, skipping..."
  else
    ssh-keygen -b 2048 -t rsa -f ~/.ssh/id_rsa -q -N ""
  fi

  echoinfo "Starting Libvirtd"
  systemctl start libvirtd || { echoerr "Unable to start libvirtd"; return 1; }


  echoinfo "Configuring Squid"
  # Allow squid client to connect to https servers other than 443
  sed -i 's/\(http_access deny !Safe_ports\)/#\1/; s/\(http_access deny CONNECT !SSL_ports\)/#\1/' /etc/squid/squid.conf 
  systemctl enable squid || { echoerr "Unable to enable Squid"; return 1; }
  systemctl start  squid || { echoerr "Unable to start Squid"; return 1; }
  firewall-cmd --permanent --add-service=squid 
  firewall-cmd --reload

}


#
#  Disable DHCP on default network + create provisioning network
#
function define_virt_net()
{

  echoinfo "---===== Create virtual networks =====---"


  cat > /tmp/provisioning.xml <<EOF
<network>
  <name>provisioning</name>
  <ip address="172.16.0.254" netmask="255.255.255.0"/>
</network>
EOF

  echoinfo "Defining provisioning network..."
  virsh net-define /tmp/provisioning.xml || { echoerr "Unable to define provisioning network"; return 1; }

  echoinfo "Setting net-autostart to provisioning network..."
  virsh net-autostart provisioning || { echoerr "Unable to configure provisioning network"; return 1; }

  echoinfo "Starting provisioning network..."
  virsh net-start provisioning || { echoerr "Unable to start provisioning network"; return 1; }

  echoinfo "Disabling DHCP on default network..."
  if(virsh net-dumpxml default | grep dhcp &>/dev/null); then
      virsh net-update default delete ip-dhcp-range "<range start='192.168.122.2' end='192.168.122.254'/>" --live --config || { echoerr "Unable to disable DHCP on default network"; return 1; }
  else
    echoinfo "DHCP already disabled, skipping"
  fi
}

#
#  Create generic RHEL image disk
#
function define_basic_image()
{

  echoinfo "---===== Create generic RHEL image =====---"

  pushd ${LIBVIRT_D}/images/
  echoinfo "Downloading basic RHEL image from $RHEL_IMAGE_U..."
  curl -o rhel7-guest-official.qcow2 $RHEL_IMAGE_U || { echoerr "Unable to download RHEL IMAGE"; return 1; }

  echoinfo "Cloning RHEL image to a 40G sparse image..."
  qemu-img create -f qcow2 rhel7-guest.qcow2 40G || { echoerr "Unable to create sparse clone"; return 1; }


  echoinfo "Checking image disk size..."
  qemu-img info rhel7-guest.qcow2  | grep 40G  &>/dev/null || { echoerr "Incorrect image disk size"; return 1; }

  echoinfo "Extending file system..."
  virt-resize --expand /dev/sda1 rhel7-guest-official.qcow2 rhel7-guest.qcow2 || { echoerr "Unable to extend file system"; return 1; }

  echoinfo "Checking image filesystem size..."
  virt-filesystems --long -h  -a rhel7-guest.qcow2 | grep 40G &> /dev/null || { echoerr "Incorrect image filesystem size"; return 1; }

  echoinfo "Deleting old image..."
  rm -f rhel7-guest-official.qcow2

  popd
}


#
#  Define & setup undercloud VM
#
function define_undercloud_vm()
{

  echoinfo "---===== Create Undercloud VM =====---"

  pushd ${LIBVIRT_D}/images/
  echoinfo "Create disk from generic image..."

  qemu-img create -f qcow2 -b rhel7-guest.qcow2 undercloud.qcow2 || { echoerr "Unable to create undercloud disk image"; return 1; }

  echoinfo "Setting password to root:redhat..."
  virt-customize -a undercloud.qcow2 --root-password password:redhat || { echoerr "Unable to change root password"; return 1; }

  echoinfo "Customizing VM..."
  virt-customize -a undercloud.qcow2 --run-command 'yum remove cloud-init* -y && cp /etc/sysconfig/network-scripts/ifcfg-eth{0,1} && sed -i s/ONBOOT=.*/ONBOOT=no/g /etc/sysconfig/network-scripts/ifcfg-eth0 && cat << EOF > /etc/sysconfig/network-scripts/ifcfg-eth1
DEVICE=eth1
ONBOOT=yes
IPADDR=192.168.122.253
NETMASK=255.255.255.0
GATEWAY=192.168.122.1
NM_CONTROLLED=no
DNS1=192.168.122.1
EOF' || { echoerr "Unable to customise undercloud VM"; return 1; }


  echoinfo "Creating undercloud VM: 4vCPUs / 16GB RAM..."
  virt-install --ram $UNDERC_MEM --vcpus $UNDERC_VCPU --os-variant rhel7 \
    --disk path=/var/lib/libvirt/images/undercloud.qcow2,device=disk,bus=virtio,format=qcow2 \
    --import --noautoconsole --vnc --network network:provisioning \
    --network network:default --name undercloud || { echoerr "Unable to create undercloud VM"; return 1; }

  popd

  echoinfo "Configuring /etc/hosts..."
  echo -e "192.168.122.253\t\tundercloud.redhat.local\tundercloud" >> /etc/hosts

  echoinfo "Waiting for undercloud to come up & Copying SSH key to undercloud..."

# Remove entry from known_host just in case
  sed -ie '/undercloud/d' ~/.ssh/known_hosts
  sleep 10
 
  local nb_tries=0       # Number of SSH connection to try
  local success=0        # Set to 1 if copy-oid worked

  until [ $nb_tries -ge 5 ]
   do

    sshpass -p 'redhat' ssh-copy-id -o StrictHostKeyChecking=no root@undercloud
    
    if [ $? -eq 0 ]; then
      success=1
      break
    fi
     
    nb_tries=$[$nb_tries+1]
    sleep 10

   done

  if [ $success -eq 0 ]; then
    echoerr "Unable to copy SSH Public key to undercloud"
    return 1
  fi


  echoinfo "SCP script to undercloud..."
  scp $WHO_I_AM root@undercloud:/tmp || { echoerr "Unable to copy $WHO_I_AM to undercloud"; return 1; }



}


#
#  Define overcloud VMs
#
function define_overcloud_vms()
{

  echoinfo "---===== Create overcloud VMs =====---"

  cd ${LIBVIRT_D}/images/

  for i in $ALL_N;
    do
      echoinfo "Creating disk image for node $i..."
      qemu-img create -f qcow2 -o preallocation=metadata overcloud-$i.qcow2 60G || { echoerr "Unable to define disk overcloud-$i.qcow2"; return 1; }
  done

  for i in $CEPH_N;
    do
        echoinfo "Creating secondary disk image for node $i..."
        qemu-img create -f qcow2 -o preallocation=metadata overcloud-$i-storage.qcow2 60G || { echoerr "Unable to define disk overcloud-$i-storage.qcow2"; return 1; }
  done

  echoinfo "Defining controller nodes..."
  echo

  for i in $CTRL_N;
  do
        echoinfo "Defining node overcloud-$i..."
        virt-install --ram $CTRL_MEM --vcpus $CTRL_VCPU --os-variant rhel7 \
        --disk path=/var/lib/libvirt/images/overcloud-$i.qcow2,device=disk,bus=virtio,format=qcow2 \
        --noautoconsole --vnc --network network:provisioning \
        --network network:default --network network:default \
        --name overcloud-$i \
        --cpu SandyBridge,+vmx \
        --dry-run --print-xml > /tmp/overcloud-$i.xml;
        virsh define --file /tmp/overcloud-$i.xml || { echoerr "Unable to define $i"; return 1; }
  done 

  echoinfo "Defining compute nodes..."
  echo

  for i in $COMPT_N;
  do
        echoinfo "Defining node overcloud-$i..."
        virt-install --ram $COMPT_MEM --vcpus $COMPT_VCPU --os-variant rhel7 \
        --disk path=/var/lib/libvirt/images/overcloud-$i.qcow2,device=disk,bus=virtio,format=qcow2 \
        --noautoconsole --vnc --network network:provisioning \
        --network network:default --network network:default \
        --name overcloud-$i \
        --cpu SandyBridge,+vmx \
        --dry-run --print-xml > /tmp/overcloud-$i.xml
        virsh define --file /tmp/overcloud-$i.xml || { echoerr "Unable to define $i"; return 1; }
  done


  echoinfo "Defining ceph nodes..."
  echo

for i in $CEPH_N;
  do
        echoinfo "Defining node overcloud-$i..."
        virt-install --ram $CEPH_MEM --vcpus $CEPH_VCPU --os-variant rhel7 \
        --disk path=/var/lib/libvirt/images/overcloud-$i.qcow2,device=disk,bus=virtio,format=qcow2 \
        --disk path=/var/lib/libvirt/images/overcloud-$i-storage.qcow2,device=disk,bus=virtio,format=qcow2 \
        --noautoconsole --vnc --network network:provisioning \
        --network network:default --network network:default \
        --name overcloud-$i \
        --cpu SandyBridge,+vmx \
        --dry-run --print-xml > /tmp/overcloud-$i.xml
        virsh define --file /tmp/overcloud-$i.xml || { echoerr "Unable to define $i"; return 1; }
  done

  echoinfo "Defining networker node..."
  echo
  echoinfo "Defining node overcloud-networker..."

  virt-install --ram $NETW_MEM --vcpus $NETW_VCPU --os-variant rhel7 \
        --disk path=/var/lib/libvirt/images/overcloud-networker.qcow2,device=disk,bus=virtio,format=qcow2 \
        --noautoconsole --vnc --network network:provisioning \
        --network network:default --network network:default \
        --name overcloud-networker \
        --cpu SandyBridge,+vmx \
        --dry-run --print-xml > /tmp/overcloud-networker.xml
  virsh define --file /tmp/overcloud-networker.xml || { echoerr "Unable to define overcloud-networker..."; return 1; }

  rm -f /tmp/overcloud-*

}


#
#  Summary output
#
function libv_post_install_output()
{

  echo
  echoinfo "---===== SUMMARY =====---"
  echo

  echo "You can connect to the undercloud VM with ssh root@undercloud / p: redhat / IP : 192.168.122.253"
  echo "Don't forget to copy your ssh key to the undercloud VM"
  echo 
  echo "Two virtual networks have been set"
  echo "- Default : 192.168.122.0/24 / GW : 192.168.122.1"
  echo "- Provisioning : 172.16.0.0/24 / GW : 172.16.0.254"
  echo
  echo "9 Overcloud VMs have been defined - List them with virsh list --all"
  echo
  echo "   
|  Node Type   | Quantity | CPU's | Memory | Storage |          Networks           |
|--------------|----------|-------|--------|---------|-----------------------------|
| Undercloud   |        1 |     ${UNDERC_VCPU} | ${UNDERC_MEM}GB | 1x40GB  | 1x Default, 1x Provisioning |
| Controller   |        3 |     $CTRL_VCPU | ${CTRL_MEM}GB | 1x60GB  | 2x Default, 1x Provisioning |
| Compute      |        2 |     $COMPT_VCPU | ${COMPT_MEM}GB | 1x60GB  | 2x Default, 1x Provisioning |
| Ceph Storage |        3 |     $CEPH_VCPU | ${CEPH_MEM}GB | 2x60GB  | 2x Default, 1x Provisioning |
| Networker    |        1 |     $NETW_VCPU | ${NETW_MEM}GB | 1x60GB  | 2x Default, 1x Provisioning |
"
  echo
  echo "Use default network for overcloud traffic - Use eth1 & eth2 for bonding"
  echo
  echoinfo "Next steps :"
  echo "---- ${RED} !!! PLEASE REBOOT YOUR SYSTEM !!! ${NORMAL}----"
  echo "- Start the undercloud VM"
  echo "- ssh to root@undercloud"
  echo "- run sh /tmp/osp-lab-deploy.sh undercloud-install as root"
  echo
  echo "Happy hacking !!! - The field PM Team"

}

function libvirt_deploy()
{

  echoinfo "Checking UID..."
  if [ $UID -ne 0 ]; then 
    echoerr "Please run this script as root"
    exit_on_err
  fi

  install_pakages "$PKG_HYPERVISOR" || exit_on_err
  check_requirements || exit_on_err
  libv_misc_sys_config || exit_on_err
  define_virt_net || exit_on_err
  define_basic_image || exit_on_err
  define_undercloud_vm || exit_on_err
  define_overcloud_vms || exit_on_err
  libv_post_install_output

}


##########################################################################
#                                                                        #
#                      Undercloud install functions                      #
#                                                                        #
##########################################################################


#
#  Miscellaneous system config
#
function undercloud_misc_sys_config()
{

  echoinfo "---===== Misc System Config =====---"

  echoinfo "Setting Hostname to undercloud.redhat.local"
  hostnamectl set-hostname undercloud.redhat.local || { echoerr "Unable to set hostname undercloud.redhat.local"; return 1; } 

  echoinfo "Restarting network service"
  systemctl  restart network || { echoerr "Unable to restart network service"; return 1; } 

  echoinfo "Populating Hosts file"
  ipaddr=$(facter ipaddress_eth1)
  echo -e "$ipaddr\t\tundercloud.redhat.local\tundercloud" >> /etc/hosts

  echoinfo "Creating system user stack..."
  useradd stack

  echoinfo "Setting stack user password to redhat"
  echo "redhat" | passwd stack --stdin

  echoinfo "Creating SSH keypair"
  if [ -e /home/stack/.ssh/id_rsa ]; then
    echoinfo "SSH keypair already exists, skipping..."
  else
    sudo -u stack ssh-keygen -b 2048 -t rsa -f /home/stack/.ssh/id_rsa -q -N ""
  fi

  echoinfo "Adding stack user to sudoers"
  echo "stack ALL=(root) NOPASSWD:ALL" | tee -a /etc/sudoers.d/stack
  chmod 0440 /etc/sudoers.d/stack

  echoinfo "Copying stack user SSH key to hypervisor..."
  sudo -u stack sshpass -p 'redhat' ssh-copy-id -o StrictHostKeyChecking=no stack@192.168.122.1 || { echoerr "Unable to copy SSH key to hypervisor - Check password authentication is enabled"; return 1; }

  echoinfo "Testing virsh connection to hypervisor"
  sudo -u stack virsh -c qemu+ssh://stack@192.168.122.1/system list || { echoerr "Unable to connect to the hypervisor"; return 1; } 

}




function configure_undercloud()
{

  echoinfo "Configuring undercloud.conf"
  sudo -u stack cp /usr/share/instack-undercloud/undercloud.conf.sample /home/stack/undercloud.conf

  sudo -u stack openstack-config --set /home/stack/undercloud.conf DEFAULT local_ip 172.16.0.1/24
  sudo -u stack openstack-config --set /home/stack/undercloud.conf DEFAULT undercloud_public_vip  172.16.0.10
  sudo -u stack openstack-config --set /home/stack/undercloud.conf DEFAULT undercloud_admin_vip 172.16.0.11
  sudo -u stack openstack-config --set /home/stack/undercloud.conf DEFAULT local_interface eth0
  sudo -u stack openstack-config --set /home/stack/undercloud.conf DEFAULT masquerade_network 172.16.0.0/24
  sudo -u stack openstack-config --set /home/stack/undercloud.conf DEFAULT dhcp_start 172.16.0.20
  sudo -u stack openstack-config --set /home/stack/undercloud.conf DEFAULT dhcp_end 172.16.0.120
  sudo -u stack openstack-config --set /home/stack/undercloud.conf DEFAULT network_cidr 172.16.0.0/24
  sudo -u stack openstack-config --set /home/stack/undercloud.conf DEFAULT network_gateway 172.16.0.1
  sudo -u stack openstack-config --set /home/stack/undercloud.conf DEFAULT discovery_iprange 172.16.0.150,172.16.0.180

}



#
#  Summary output
#
function undercloud_post_install_output()
{

  echo
  echoinfo "---===== SUMMARY =====---"
  echo

  echo "Base system and undercloud configuration completed !"
  echoinfo "Next steps :"
  echo "- !!!! REBOOT the undercloud VM !!!!"
  echo "- Check ~stack/undercloud.conf file"
  echo "- Run openstack undercloud install as stack user"
  echo "- Check the undercloud install is successful"
  echo "- Run osp-lab-deploy.sh overcloud-register as stack user"

}


function undercloud_install()
{

  echoinfo "Checking UID..."
  if [ $UID -ne 0 ]; then 
    echoerr "Please run this script as root"
    exit_on_err
  fi


  install_pakages "$PKG_UNDERCLOUD" || exit_on_err
  undercloud_misc_sys_config || exit_on_err
  configure_undercloud || exit_on_err
  undercloud_post_install_output

}


##########################################################################
#                                                                        #
#                Undercloud node registration functions                  #
#                                                                        #
##########################################################################



function upload_overcloud_image()
{

  echoinfo "---===== Upload Overcloud images =====---"

  echoinfo "Installing package rhosp-director-images..."
  sudo yum install rhosp-director-images -y || { echoerr "Unable to install package rhosp-director-images"; return 1; } 

  echoinfo "Create /home/stack/images directory"
  mkdir -p ~/images/
  cd  ~/images/

  echoinfo "Extracting IPA image to ~/images..."
  tar xvf /usr/share/rhosp-director-images/ironic-python-agent.tar -C . || { echoerr "Unable to extract IPA image"; return 1; } 

  echoinfo "Extracting overcloud image to ~/images..."
  tar xvf /usr/share/rhosp-director-images/overcloud-full.tar -C . || { echoerr "Unable to extract overcloud images"; return 1; } 

  echoinfo "Setting image's root password to redhat..."
  virt-customize -a ~/images/overcloud-full.qcow2 --root-password password:redhat || { echoerr "Unable to set root password into the image"; return 1; } 

  echoinfo "Uploading images to glance"
  openstack overcloud image upload || { echoerr "Failed to upload images to glance"; return 1; } 
}



function register_overcloud_nodes()
{
  echoinfo "---===== Registering overcloud images =====---"
  
  cd ~
  echoinfo "Dumping overcloud's nodes provisioning MAC addresses to /tmp/nodes.txt"
  for i in $ALL_N; do 
    echoinfo "Looking for node $i"
    virsh -c qemu+ssh://stack@192.168.122.1/system  domiflist overcloud-$i | awk '$3 == "provisioning" {print $5};' || { echoerr "Unable to get MAC address of node $i"; return 1; } 
  done > /tmp/nodes.txt

  echoinfo "Generating ~/instackenv.json file"

  jq . << EOF > ~/instackenv.json
{
  "nodes": [
    {
      "name": "overcloud-ctrl01",
      "cpu":"4",
      "memory":"6144",
      "disk":"40",
      "arch":"x86_64",
      "pm_addr": "192.168.122.1",
      "pm_password": "$(cat ~/.ssh/id_rsa)",
      "pm_type": "pxe_ssh",
      "mac": [
        "$(sed -n 1p /tmp/nodes.txt)"
      ],
      "pm_user": "stack"
    },
    {
      "name": "overcloud-ctrl02",
      "cpu":"4",
      "memory":"6144",
      "disk":"40",
      "arch":"x86_64",
      "pm_addr": "192.168.122.1",
      "pm_password": "$(cat ~/.ssh/id_rsa)",
      "pm_type": "pxe_ssh",
      "mac": [
        "$(sed -n 2p /tmp/nodes.txt)"
      ],
      "pm_user": "stack"
    },
    {
      "name": "overcloud-ctrl03",
      "cpu":"4",
      "memory":"6144",
      "disk":"40",
      "arch":"x86_64",
      "pm_addr": "192.168.122.1",
      "pm_password": "$(cat ~/.ssh/id_rsa)",
      "pm_type": "pxe_ssh",
      "mac": [
        "$(sed -n 3p /tmp/nodes.txt)"
      ],
      "pm_user": "stack"
    },
    {
      "name": "overcloud-compute01",
      "cpu":"4",
      "memory":"6144",
      "disk":"40",
      "arch":"x86_64",
      "pm_addr": "192.168.122.1",
      "pm_password": "$(cat ~/.ssh/id_rsa)",
      "pm_type": "pxe_ssh",
      "mac": [
        "$(sed -n 4p /tmp/nodes.txt)"
      ],
      "pm_user": "stack"
    },
    {
      "name": "overcloud-compute02",
      "cpu":"4",
      "memory":"6144",
      "disk":"40",
      "arch":"x86_64",
      "pm_addr": "192.168.122.1",
      "pm_password": "$(cat ~/.ssh/id_rsa)",
      "pm_type": "pxe_ssh",
      "mac": [
        "$(sed -n 5p /tmp/nodes.txt)"
      ],
      "pm_user": "stack"
    },
    {
      "name": "overcloud-ceph01",
      "cpu":"4",
      "memory":"6144",
      "disk":"40",
      "arch":"x86_64",
      "pm_addr": "192.168.122.1",
      "pm_password": "$(cat ~/.ssh/id_rsa)",
      "pm_type": "pxe_ssh",
      "mac": [
        "$(sed -n 6p /tmp/nodes.txt)"
      ],
      "pm_user": "stack"
    },
    {
      "name": "overcloud-ceph02",
      "cpu":"4",
      "memory":"6144",
      "disk":"40",
      "arch":"x86_64",
      "pm_addr": "192.168.122.1",
      "pm_password": "$(cat ~/.ssh/id_rsa)",
      "pm_type": "pxe_ssh",
      "mac": [
        "$(sed -n 7p /tmp/nodes.txt)"
      ],
      "pm_user": "stack"
    },
    {
      "name": "overcloud-ceph03",
      "cpu":"4",
      "memory":"6144",
      "disk":"40",
      "arch":"x86_64",
      "pm_addr": "192.168.122.1",
      "pm_password": "$(cat ~/.ssh/id_rsa)",
      "pm_type": "pxe_ssh",
      "mac": [
        "$(sed -n 8p /tmp/nodes.txt)"
      ],
      "pm_user": "stack"
    },
    {
      "name": "overcloud-networker",
      "cpu":"4",
      "memory":"6144",
      "disk":"40",
      "arch":"x86_64",
      "pm_addr": "192.168.122.1",
      "pm_password": "$(cat ~/.ssh/id_rsa)",
      "pm_type": "pxe_ssh",
      "mac": [
        "$(sed -n 9p /tmp/nodes.txt)"
      ],
      "pm_user": "stack"
    }
  ]
}
EOF

  echoinfo "Validating instackenv file..."
  openstack baremetal instackenv validate || { echoerr "instackenv validation failed !"; return 1; } 

  echoinfo "Importing overcloud nodes to Ironic..."
  openstack baremetal import --json instackenv.json ||  { echoerr "Failed to import nodes !"; return 1; } 

}

function introspect_nodes()
{
  echoinfo "---===== Instrospect overcloud images =====---"
  
  echoinfo "Setting nodes to manage state..."
  for i in $(ironic node-list | awk ' /overcloud/ {print $2;}'); do 
    echoinfo "Setting $i to manage state"
    ironic node-set-provision-state $i manage  ||  { echoerr "Unable to set $i to manage state !"; return 1; } 
  done

  echoinfo "Starting instrospection..."
  #openstack overcloud node introspect --all-manageable --provide ||  { echoerr "Instrospection failed !"; return 1; } 
  openstack baremetal introspection bulk start ||  { echoerr "Instrospection failed !"; return 1; } 
  openstack baremetal introspection bulk status

  echoinfo "Configuring boot on overcloud nodes..."
  openstack baremetal configure boot ||  { echoerr "Unable to configure boot on overcloud nodes !"; return 1; } 

  echoinfo "Setting DNS to 192.168.122.1 on Neutron provisioning network..."
  subnet_id=$(neutron subnet-list | awk '/172.16.0.0/ {print $2;}')
  neutron subnet-update $subnet_id --dns-nameserver 192.168.122.1

}

function tag_overcloud_nodes()
{

  echoinfo "---===== Tag overcloud images =====---"

  echoinfo "Tagging controllers nodes to control profile..."
  for i in $CTRL_N; do
    echoinfo "Tagging $i..."
    ironic node-update overcloud-$i add properties/capabilities='profile:control,boot_option:local' ||  { echoerr "Tagging of node $i failed !"; return 1; } 
  done

  echoinfo "Tagging Ceph nodes to ceph-storage profile..."
  for i in $CEPH_N; do
    echoinfo "Tagging $i..."
    ironic node-update overcloud-$i add properties/capabilities='profile:ceph-storage,boot_option:local' ||  { echoerr "Tagging of node $i failed !"; return 1; } 
  done

  echoinfo "Tagging compute nodes to compute profile..."
  for i in $COMPT_N; do
    echoinfo "Tagging $i..."
    ironic node-update overcloud-$i add properties/capabilities='profile:compute,boot_option:local' ||  { echoerr "Tagging of node $i failed !"; return 1; } 
  done


  echoinfo "Tagging networker node to networker profile..."
  ironic node-update overcloud-networker add properties/capabilities='profile:networker,boot_option:local' ||  { echoerr "Tagging of networker node failed !"; return 1; } 


  echoinfo "Creating networker flavor..."
  openstack flavor create --id auto --ram 4096 --disk 40 --vcpus 1 networker ||  { echoerr "Unable to create networker flavor !"; return 1; } 
  openstack flavor set  --property "capabilities:boot_option"="local" --property "capabilities:profile"="networker" networker ||  { echoerr "Unable to configure networker flavor !"; return 1; } 

}

function overcloud_reg_post_install_output()
{

  echoinfo "Sucessfully uploaded overcloud image to glance"
  echoinfo "Sucessfully register overcloud nodes to ironic : $ALL_N"
  echoinfo "source ~/stackrc to start playing !!!" 
  echo
  echo "Happy hacking !!! - The field PM Team"


}

function overcloud_register()
{

  echoinfo "Checking UID..."
  if [ $USER != "stack" ]; then 
    echoerr "Please run this script as stack user"
    exit_on_err
  else
    source ~/stackrc || { echoerr "Unable to source ~/stackrc - Have you installed the undercloud ???"; exit_on_err; } 
  fi


  upload_overcloud_image || exit_on_err
  register_overcloud_nodes || exit_on_err
  introspect_nodes || exit_on_err
  tag_overcloud_nodes || exit_on_err

  echoinfo "All set ! You're good to go !"


}


##########################################################################
#                                                                        #
#                             Main function                              #
#                                                                        #
##########################################################################


case $1 in
  "libvirt-deploy")
    echoinfo "Starting libvirt deployment..."
    libvirt_deploy
   ;;

  "undercloud-install")    
    echoinfo "Starting undercloud installation..."
    undercloud_install
  ;;
  "overcloud-register")
    echoinfo "Starting undercloud nodes registration..."
    overcloud_register
  ;;
  "howto")
    howto
  ;;
*)
  echo "Invalid argument"
  help
  ;;
esac
