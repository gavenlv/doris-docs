#!/bin/bash

set -e

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <be_number> <be_ip> [terraform_vars_file]"
    echo "Example: $0 3 10.0.0.23 terraform.tfvars.1fe2be"
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
resource "google_compute_instance" "be${BE_NUM}" {
  name         = "${cluster_name}-be-${BE_NUM}"
  machine_type = var.be_machine_type
  zone         = var.zone

  tags = ["doris-be", local.cluster_name]

  boot_disk {
    initialize_params {
      image  = var.image_family
      labels = {}
      size   = var.be_disk_size
      type   = var.be_disk_type
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.doris_subnet.id
    access_config {
      network_tier = "PREMIUM"
    }
    network_ip = "${BE_IP}"
  }

  metadata = {
    ssh-keys = "\${var.ssh_user}:\${file(var.ssh_public_key_path)}"
    user-data = templatefile("\${path.module}/user-data-be.sh", {
      cluster_name = var.cluster_name
      fe_servers  = var.fe_servers
      be_id       = "${BE_NUM}"
    })
  }

  scheduling {
    preemptible = var.be_preemptible
  }

  lifecycle {
    create_before_destroy = true
  }
}
EOF

echo ""
echo "After updating files, run:"
echo "  terraform plan -var-file=${TFVARS_FILE}"
echo "  terraform apply -var-file=${TFVARS_FILE}"
echo ""
echo "Finally, add the BE to Doris cluster:"
echo "  mysql -h <FE_IP> -P 9030 -u root -e \"ALTER SYSTEM ADD BACKEND '${BE_IP}:9050';\""
