#!/bin/sh

echo "Removing debris"
rm -f work_config:Wq
rm -f vm?.xml
rm -f networks/*
rm docker/certs/*
rm docker/etc/*
rm -r config-drives/vm1-config/certs/
rm -r config-drives/vm1-config/etc/
rm config-drives/vm1-config/docker-compose.yml
rm config-drives/vm1-config/user-data
rm config-drives/vm1-config/meta-data
rm config-drives/vm2-config/docker-compose.yml
rm config-drives/vm2-config/user-data
rm config-drives/vm2-config/meta-data
rm work_config

virsh net-destroy external
virsh net-destroy internal
virsh net-destroy management

virsh net-undefine external
virsh net-undefine internal
virsh net-undefine management

virsh destroy vm1
virsh destroy vm2

virsh undefine vm1
virsh undefine vm2



