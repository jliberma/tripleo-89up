#!/usr/bin/env bash
# sudo sh install_cacert.sh

cp /home/stack/templates/overcloud-cacert.pem /etc/pki/ca-trust/source/anchors/
ls /etc/pki/ca-trust/source/anchors/
update-ca-trust extract
