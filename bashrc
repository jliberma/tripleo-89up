# .bashrc

# Source global definitions
if [ -f /etc/bashrc ]; then
      . /etc/bashrc
fi

# Uncomment the following line if you don't like systemctl's auto-paging feature:
# export SYSTEMD_PAGER=

# User specific aliases and functions
function overcloud-etc-hosts() {
    sudo sed -i -e '/inlunch-generated/d' /etc/hosts
    nova list | grep overcloud- | awk '{ print $12 " " $4 "  # inlunch-generated" }' | sed -e 's/ctlplane=//' | sudo tee -a /etc/hosts
}


function run-on-overcloud() {
    for i in $(nova list|grep ctlplane|awk -F' ' '{ print $12 }'|awk -F'=' '{ print $2 }'); do
        j=$(grep $i /etc/hosts | awk ' { print $2 } ' )
        printf $j:; ssh -o StrictHostKeyChecking=no heat-admin@$i "$@"
    done
}

 

function ctl-health() {
    for i in $(openstack server list | awk ' /controller/ { print $8 } ' | sed -e 's/ctlplane=//'); do
        j=$(grep $i /etc/hosts | awk ' { print $2 } ' )
        printf $j:; ssh -o StrictHostKeyChecking=no heat-admin@$i "sudo pcs status | egrep -i 'stop|fail|unmanaged'; systemctl list-units 'openvswitch' 'openstack-\*' 'neutron-\*' | egrep -i 'fail|stop|error'"
        echo -e
    done
}
