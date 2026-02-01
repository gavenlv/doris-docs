output "connection_info" {
  description = "Cluster connection information"
  value = {
    fe_count           = var.fe_count
    be_count           = var.be_count
    fe_ips             = google_compute_instance_from_template.fe_instances[*].network_interface[0].access_config[0].nat_ip
    fe_internal_ips    = google_compute_instance_from_template.fe_instances[*].network_interface[0].network_ip
    be_ips             = var.enable_autoscaling ? [] : google_compute_instance_from_template.be_instances[*].network_interface[0].access_config[0].nat_ip
    lb_internal_ip     = var.enable_load_balancer ? google_compute_forwarding_rule.fe_forwarding_rule[0].ip_address : null
    ssh_user           = var.ssh_user
    fe_port            = "9030"
    be_port            = "9050"
    enable_autoscaling = var.enable_autoscaling
    enable_load_balancer = var.enable_load_balancer
    enable_storage_separation = var.enable_compute_storage_separation
    gcs_bucket         = var.enable_compute_storage_separation ? var.gcs_bucket_name : null
  }
}

output "terraform_state" {
  description = "Terraform state file location"
  value       = "terraform.tfstate"
}

output "deployment_commands" {
  description = "Useful deployment and management commands"
  value = {
    deploy_dev      = "terraform apply -var-file=terraform.tfvars.dev"
    deploy_sit      = "terraform apply -var-file=terraform.tfvars.sit"
    deploy_uat      = "terraform apply -var-file=terraform.tfvars.uat"
    deploy_prod     = "terraform apply -var-file=terraform.tfvars.prod"
    destroy         = "terraform destroy -var-file=<environment>"
    scale_up        = "terraform apply -var 'be_count=<new_count>' -var-file=<environment>"
    scale_down      = "terraform apply -var 'be_count=<new_count>' -var-file=<environment>"
  }
}
