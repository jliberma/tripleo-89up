# tripleo-89up

A collection of Heat templates for upgrading from tripleo Liberty to Mitaka.

This environment includes the following customisations:

 1. Network isolation + bonding
 2. Director-installed Ceph OSDs + monitors
 3. Setting timezone
 4. TLS SSL encryption on public endpoints

Workflow

 1. Deploy overcloud with customisations
 2. Update undercloud to latest version of OSP 8
    1. reboot undercloud if kernel or openvswitch version changes
 3. Update overcloud to latest version of OSP 8
 4. Update overcloud images to latest version of OSP 8
    1. reboot overcloud nodes if kernel or openvswitch version changes
 5. Upgrade undercloud to OSP 9
 6. Install OSP 9 overcloud images
 7. Add new TLS endpoints to enable-tls.yaml
 8. Create new Ceph client key for director-deployed Ceph
 9. Run Aodh migration
    1. it is possible to remove ceilometer-[alarm,notification] pcs services, resources, and rpm pkg prior to this step
    2. Aodh migration and Keystone migration, steps 9 & 10, require OSP 8 repos on overcloud
 1. Migrate Keystone to WSGI
 2. Add OSP 9 repos to the overcloud either before or during the pacemaker-init step
 3. Run major-upgrade-pacemaker-init
    1. Make sure all pcs services are online and running after steps 3, 9, 10, 11, 12
 13. Update object storage nodes if present
 14. Update controller nodes
    1. reboot controllers if kernel or openvswitch version changes
    2. controllers must be rebooted one at a time to preserve HA
    3. make sure all pcs services are up and running on all nodes before rebooting a node
 15. Upgrade the Ceph nodes
    1. Reboot if kernel or openvswitch version changes
    2. Requires setting noout and norebalance then rebooting OSDs one at a time
    3. check ceph health and PG map health after each OSD reboot
 16. Update compute nodes
    1. Disable nova-compute and migrate instances off each compute node before updating
    2. after updating compute, reboot if kernel or openvswitch version changes
    3. re-enable nova-compute and migrate instances back before proceeding to the next compute
 17. Run final converge deploy command with --force-postconfig switch
    1. make sure all pcs services are up and running after converge
    2. verify new service endpoints are accessible: sahara, aodh, gnocchi
