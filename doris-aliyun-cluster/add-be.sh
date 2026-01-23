#!/bin/bash

set -e

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <be_number> <be_ip> [terraform_vars_file]"
    echo "Example: $0 3 172.16.0.23 terraform.tfvars.1fe2be"
    exit 1
fi

BE_NUM=$1
BE_IP=$2
TFVARS_FILE=${3:-terraform.tfvars.1fe2be}

echo "Adding BE${BE_NUM} with IP: ${BE_IP}"
echo "Using Terraform vars file: ${TFVARS_FILE}"

# Check if terraform.tfvars file exists
if [ ! -f "${TFVARS_FILE}" ]; then
    echo "Error: ${TFVARS_FILE} not found!"
    exit 1
fi

# Add BE configuration to terraform.tfvars
echo ""
echo "Please add the following to ${TFVARS_FILE}:"
echo ""
echo "be_count = $((BE_NUM))"
echo ""

# Add BE service to main.tf
echo ""
echo "Please add the following BE service to main.tf (if not using instance templates):"
echo ""
cat <<EOF
resource "alicloud_instance" "be${BE_NUM}" {
  count                = 1
  instance_name        = "\${local.cluster_name}-be-${BE_NUM}"
  image_id             = var.image_id
  instance_type        = var.be_instance_type
  system_disk_category = var.be_disk_category
  system_disk_size     = var.be_disk_size
  vswitch_id          = alicloud_vswitch.doris_vswitch.id
  security_groups      = [alicloud_security_group.doris_sg.id]
  key_name            = alicloud_key_pair.doris_key.key_pair_name
  internet_max_bandwidth_out = var.internet_bandwidth

  user_data = templatefile("\${path.module}/user-data-be.sh", {
    cluster_name = var.cluster_name
    fe_servers  = var.fe_servers
    be_id       = "${BE_NUM}"
  })

  tags = {
    Name = "\${local.cluster_name}-be-${BE_NUM}"
    Role = "be"
  }

  spot_strategy = var.be_spot_strategy
}
EOF

echo ""
echo "Please add the following EIP and association:"
echo ""
cat <<EOF
resource "alicloud_eip" "be${BE_NUM}_eip" {
  count                = 1
  bandwidth            = var.internet_bandwidth
  internet_charge_type = "PayByTraffic"
}

resource "alicloud_eip_association" "be${BE_NUM}_eip_association" {
  count         = 1
  allocation_id = alicloud_eip.be${BE_NUM}_eip[0].id
  instance_id   = alicloud_instance.be${BE_NUM}[0].id
}
EOF

echo ""
echo "After updating files, run:"
echo "  terraform plan -var-file=${TFVARS_FILE}"
echo "  terraform apply -var-file=${TFVARS_FILE}"
echo ""
echo "Finally, add BE to Doris cluster:"
echo "  mysql -h <FE_PUBLIC_IP> -P 9030 -u root -e \"ALTER SYSTEM ADD BACKEND '${BE_IP}:9050';\""
