#!/bin/bash

ssh-keygen -f ~/nova_rsa -t rsa -N ''

ALLCOMPUTES=$(openstack server list --name ".*compute.*" -c Networks -f csv --quote none | tail -n+2 | awk -F '=' '{ print $2 }')

for COMPUTE in $ALLCOMPUTES
do
  ssh heat-admin@$COMPUTE "sudo usermod -s /bin/bash nova"
  ssh heat-admin@$COMPUTE "sudo mkdir -p /var/lib/nova/.ssh"
  scp ~/nova* heat-admin@$COMPUTE:~/
  ssh heat-admin@$COMPUTE "sudo cp ~/nova_rsa /var/lib/nova/.ssh/id_rsa"
  ssh heat-admin@$COMPUTE "sudo cp ~/nova_rsa.pub /var/lib/nova/.ssh/id_rsa.pub"
  ssh heat-admin@$COMPUTE "sudo rm ~/nova_rsa*"
  ssh heat-admin@$COMPUTE "echo 'StrictHostKeyChecking no'|sudo tee -a /var/lib/nova/.ssh/config"
  ssh heat-admin@$COMPUTE "sudo cat /var/lib/nova/.ssh/id_rsa.pub|sudo tee -a /var/lib/nova/.ssh/authorized_keys"
  ssh heat-admin@$COMPUTE "sudo chown -R nova: /var/lib/nova/.ssh"
  ssh heat-admin@$COMPUTE "sudo su -c 'chmod 600 /var/lib/nova/.ssh/*' nova"
  ssh heat-admin@$COMPUTE "sudo chmod 700 /var/lib/nova/.ssh"
done

rm ~/nova_rsa*
