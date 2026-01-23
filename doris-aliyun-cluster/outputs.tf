output "connection_info" {
  description = "Cluster connection information"
  value = {
    fe_count    = var.fe_count
    be_count    = var.be_count
    fe_public_ips   = alicloud_eip.fe_eips[*].ip_address
    be_public_ips   = alicloud_eip.be_eips[*].ip_address
    fe_private_ips  = alicloud_instance.fe_instances[*].private_ip
    be_private_ips  = alicloud_instance.be_instances[*].private_ip
    key_pair_name = alicloud_key_pair.doris_key.key_pair_name
    fe_port     = "9030"
    be_port     = "9050"
    region       = var.region
    zone         = var.zone
  }
}

output "vpc_id" {
  description = "VPC ID"
  value       = alicloud_vpc.doris_vpc.id
}

output "vswitch_id" {
  description = "VSwitch ID"
  value       = alicloud_vswitch.doris_vswitch.id
}

output "security_group_id" {
  description = "Security Group ID"
  value       = alicloud_security_group.doris_sg.id
}
