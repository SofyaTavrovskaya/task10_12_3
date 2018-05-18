#!/bin/bash

echo "Export variables from config file"
source config
export $(cut -d= -f1 config| grep -v '^$\|^\s*\#' config)
envsubst < config > work_config
source work_config
export $(cut -d= -f1 work_config| grep -v '^$\|^\s*\#' work_config)


echo "Create directory for config-drives for vm1 and vm2"
mkdir -p config-drives/$VM1_NAME-config config-drives/$VM2_NAME-config


echo "Download Ubuntu cloud image, if it doesn't exist"
wget -O /var/lib/libvirt/images/ubuntu-server-16.04.qcow2 -nc $VM_BASE_IMAGE

echo "Dropping old VM images"
rm -f $VM1_HDD
rm -f $VM2_HDD

echo "Create two snapshots from clean image"
qemu-img create -f qcow2 -b /var/lib/libvirt/images/ubuntu-server-16.04.qcow2 $VM1_HDD
qemu-img create -f qcow2 -b /var/lib/libvirt/images/ubuntu-server-16.04.qcow2 $VM2_HDD

echo "Generate MAC adress for external network"
export MAC_VM1_EXT=52:54:00:`(date; cat /proc/interrupts) | md5sum | sed -r 's/^(.{6}).*$/\1/; s/([0-9a-f]{2})/\1:/g; s/:$//;'`

echo "Create directory for libvirt network XMLs"
mkdir -p networks/

echo "Create external.xml from template"
envsubst < templates/external_template.xml > networks/external.xml

echo "Create internal.xml from template"
envsubst < templates/internal_template.xml > networks/internal.xml

echo "Create management.xml from template"
envsubst < templates/management_template.xml > networks/management.xml

echo "Create networks from XML templates"
virsh net-define networks/external.xml
virsh net-define networks/internal.xml
virsh net-define networks/management.xml

echo "Start networks"
virsh net-start external
virsh net-start internal
virsh net-start management

echo "Create meta-data for VMs"
envsubst < templates/meta-data_VM1_template > config-drives/vm1-config/meta-data
envsubst < templates/meta-data_VM2_template > config-drives/vm2-config/meta-data

echo "Create user-data for VM1"
envsubst < templates/user-data_VM1_template > config-drives/vm1-config/user-data
cat <<EOT >> config-drives/vm1-config/user-data
ssh_authorized_keys:
 - $(cat $SSH_PUB_KEY)
EOT

echo "Create user-data for VM2"
envsubst < templates/user-data_VM2_template > config-drives/vm2-config/user-data
cat <<EOT >> config-drives/vm2-config/user-data
ssh_authorized_keys:
 - $(cat $SSH_PUB_KEY) 
EOT

echo "Create VM1.xml and VM2.xml from template"
envsubst < templates/vm1_template.xml > vm1.xml
envsubst < templates/vm2_template.xml > vm2.xml

echo "Create docker-compose.yml for VM1 and VM2 from template"
envsubst < templates/docker-compose_template_VM1.yml > config-drives/vm1-config/docker-compose.yml
envsubst < templates/docker-compose_template_VM2.yml > config-drives/vm2-config/docker-compose.yml

echo "Create directory for docker"
mkdir -p docker/etc docker/certs

echo "Create nginx.conf from template"
envsubst < templates/nginx_template.conf > docker/etc/nginx.conf

if [ ! -e docker/certs/root.key ]
then
echo "Root key is absent, generating"
openssl genrsa -out docker/certs/root.key 4096
else
echo "Root key present"
fi

echo "Generating root csr"
openssl req -new -nodes\
    -keyout docker/certs/root.key\
    -out docker/certs/root.csr\
    -subj "/C=UA/ST=Kharkov/L=Kharkov/O=Mirantis/OU=dev_ops/CN=${VM1_NAME}/"

echo "Generating root certificate"
openssl x509 -req\
    -signkey docker/certs/root.key\
    -in docker/certs/root.csr\
    -out docker/certs/root.crt

echo "Generating web.key"
openssl genrsa -out docker/certs/web.key 2048

echo "Generating web.csr"
openssl req -new\
    -key docker/certs/web.key\
    -out docker/certs/web.csr\
    -subj "/C=UA/ST=Kharkov/L=Kharkov/O=Mirantis/OU=dev_ops/CN=${VM1_NAME}/"

echo "Generating web.crt"
openssl x509 -req\
    -in docker/certs/web.csr\
    -CA docker/certs/root.crt\
    -CAkey docker/certs/root.key\
    -CAcreateserial\
    -out docker/certs/web.crt\
    -extfile <(printf "subjectAltName=IP:${VM1_EXTERNAL_IP},DNS:${VM1_NAME}")

cat docker/certs/root.crt docker/certs/web.crt  > docker/certs/web-ca-chain.pem

echo "Create config drives"
mkisofs -o "$VM1_CONFIG_ISO" -V cidata -r -J --quiet config-drives/vm1-config
mkisofs -o "$VM2_CONFIG_ISO" -V cidata -r -J --quiet config-drives/vm2-config

echo "Define VMs from XML templates"
virsh define vm1.xml
virsh define vm2.xml

echo "Start VMs"
virsh start vm1

virsh start vm2
