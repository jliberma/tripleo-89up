#!/bin/bash

exec openstack overcloud update stack overcloud -i \
        --templates /usr/share/openstack-tripleo-heat-templates \
        --timeout 90 \
        -e /usr/share/openstack-tripleo-heat-templates/overcloud-resource-registry-puppet.yaml \
        -e /home/stack/templates/timezone.yaml \
        -e /usr/share/openstack-tripleo-heat-templates/environments/network-isolation.yaml \
        -e /home/stack/templates/network-environment.yaml \
        -e /home/stack/templates/enable-tls.yaml \
        -e /home/stack/templates/inject-trust-anchor.yaml \
        -e /home/stack/templates/environments/storage-environment.yaml
