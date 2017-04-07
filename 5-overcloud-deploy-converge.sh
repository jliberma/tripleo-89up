#!/bin/bash

exec openstack overcloud deploy \
        --force-postconfig \
        --templates /usr/share/openstack-tripleo-heat-templates \
        --ntp-server 10.16.255.1 \
        --control-flavor control --control-scale 3 \
        --compute-flavor compute --compute-scale 2 \
        --ceph-storage-flavor ceph-storage --ceph-storage-scale 3 \
        --neutron-tunnel-types vxlan --neutron-network-type vxlan \
        -e /home/stack/templates/timezone.yaml \
        -e /usr/share/openstack-tripleo-heat-templates/environments/network-isolation.yaml \
        -e /home/stack/templates/network-environment.yaml \
        -e /home/stack/templates/enable-tls.yaml \
        -e /home/stack/templates/inject-trust-anchor.yaml \
        -e /home/stack/templates/ceph-key.yaml \
        -e /home/stack/templates/environments/storage-environment.yaml \
        -e /usr/share/openstack-tripleo-heat-templates/environments/major-upgrade-pacemaker-converge.yaml
