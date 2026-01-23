terraform {
  required_providers {
    alicloud = {
      source  = "aliyun/alicloud"
      version = "~> 1.200"
    }
  }
}

provider "alicloud" {
  region = var.region
}

locals {
  cluster_name = "${var.cluster_name}-${var.environment}"
}

resource "alicloud_vpc" "doris_vpc" {
  vpc_name   = "${local.cluster_name}-vpc"
  cidr_block = var.vpc_cidr
}

resource "alicloud_vswitch" "doris_vswitch" {
  vpc_id     = alicloud_vpc.doris_vpc.id
  cidr_block = var.vswitch_cidr
  zone_id    = var.zone
}

resource "alicloud_security_group" "doris_sg" {
  name   = "${local.cluster_name}-sg"
  vpc_id = alicloud_vpc.doris_vpc.id
}

resource "alicloud_security_group_rule" "allow_internal" {
  type              = "ingress"
  ip_protocol       = "all"
  port_range        = "1/65535"
  security_group_id = alicloud_security_group.doris_sg.id
  cidr_ip          = var.vswitch_cidr
}

resource "alicloud_security_group_rule" "allow_external" {
  type              = "ingress"
  ip_protocol       = "tcp"
  port_range        = "9030/9032"
  security_group_id = alicloud_security_group.doris_sg.id
  cidr_ip          = "0.0.0.0/0"
}

resource "alicloud_security_group_rule" "allow_http" {
  type              = "ingress"
  ip_protocol       = "tcp"
  port_range        = "8030/8032"
  security_group_id = alicloud_security_group.doris_sg.id
  cidr_ip          = "0.0.0.0/0"
}

resource "alicloud_security_group_rule" "allow_edit_log" {
  type              = "ingress"
  ip_protocol       = "tcp"
  port_range        = "9010/9012"
  security_group_id = alicloud_security_group.doris_sg.id
  cidr_ip          = "0.0.0.0/0"
}

resource "alicloud_security_group_rule" "allow_ssh" {
  type              = "ingress"
  ip_protocol       = "tcp"
  port_range        = "22/22"
  security_group_id = alicloud_security_group.doris_sg.id
  cidr_ip          = "0.0.0.0/0"
}

resource "alicloud_key_pair" "doris_key" {
  key_pair_name = "${local.cluster_name}-key"
}

resource "alicloud_instance" "fe_instances" {
  count                = var.fe_count
  instance_name        = "${local.cluster_name}-fe-${count.index + 1}"
  image_id             = var.image_id
  instance_type        = var.fe_instance_type
  system_disk_category = var.fe_disk_category
  system_disk_size     = var.fe_disk_size
  vswitch_id          = alicloud_vswitch.doris_vswitch.id
  security_groups      = [alicloud_security_group.doris_sg.id]
  key_name            = alicloud_key_pair.doris_key.key_pair_name
  internet_max_bandwidth_out = var.internet_bandwidth

  user_data = templatefile("${path.module}/user-data-fe.sh", {
    cluster_name = var.cluster_name
    fe_servers  = var.fe_servers
    fe_id       = "${count.index + 1}"
  })

  tags = {
    Name = "${local.cluster_name}-fe-${count.index + 1}"
    Role = "fe"
  }

  spot_strategy = var.fe_spot_strategy
}

resource "alicloud_instance" "be_instances" {
  count                = var.be_count
  instance_name        = "${local.cluster_name}-be-${count.index + 1}"
  image_id             = var.image_id
  instance_type        = var.be_instance_type
  system_disk_category = var.be_disk_category
  system_disk_size     = var.be_disk_size
  vswitch_id          = alicloud_vswitch.doris_vswitch.id
  security_groups      = [alicloud_security_group.doris_sg.id]
  key_name            = alicloud_key_pair.doris_key.key_pair_name
  internet_max_bandwidth_out = var.internet_bandwidth

  user_data = templatefile("${path.module}/user-data-be.sh", {
    cluster_name = var.cluster_name
    fe_servers  = var.fe_servers
    be_id       = "${count.index + 1}"
  })

  tags = {
    Name = "${local.cluster_name}-be-${count.index + 1}"
    Role = "be"
  }

  spot_strategy = var.be_spot_strategy
}

resource "alicloud_eip" "fe_eips" {
  count                = var.fe_count
  bandwidth            = var.internet_bandwidth
  internet_charge_type = "PayByTraffic"
}

resource "alicloud_eip_association" "fe_eip_associations" {
  count         = var.fe_count
  allocation_id = alicloud_eip.fe_eips[count.index].id
  instance_id   = alicloud_instance.fe_instances[count.index].id
}

resource "alicloud_eip" "be_eips" {
  count                = var.be_count
  bandwidth            = var.internet_bandwidth
  internet_charge_type = "PayByTraffic"
}

resource "alicloud_eip_association" "be_eip_associations" {
  count         = var.be_count
  allocation_id = alicloud_eip.be_eips[count.index].id
  instance_id   = alicloud_instance.be_instances[count.index].id
}

output "fe_public_ips" {
  description = "FE instance public IPs"
  value       = alicloud_eip.fe_eips[*].ip_address
}

output "be_public_ips" {
  description = "BE instance public IPs"
  value       = alicloud_eip.be_eips[*].ip_address
}

output "fe_private_ips" {
  description = "FE instance private IPs"
  value       = alicloud_instance.fe_instances[*].private_ip
}

output "be_private_ips" {
  description = "BE instance private IPs"
  value       = alicloud_instance.be_instances[*].private_ip
}

output "key_pair_name" {
  description = "SSH key pair name"
  value       = alicloud_key_pair.doris_key.key_pair_name
}

output "cluster_info" {
  description = "Cluster connection information"
  value = {
    fe_count = var.fe_count
    be_count = var.be_count
    fe_port  = "9030"
    be_port  = "9050"
  }
}
