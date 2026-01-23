output "connection_info" {
  description = "Cluster connection information"
  value = {
    fe_count = var.fe_count
    be_count = var.be_count
    fe_ips    = google_compute_instance_from_template.fe_instances[*].network_interface[0].access_config[0].nat_ip
    be_ips    = google_compute_instance_from_template.be_instances[*].network_interface[0].access_config[0].nat_ip
    ssh_user  = var.ssh_user
    fe_port   = "9030"
    be_port   = "9050"
  }
}

output "terraform_state" {
  description = "Terraform state file location"
  value       = "terraform.tfstate"
}
