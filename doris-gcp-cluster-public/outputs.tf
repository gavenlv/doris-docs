output "connection_info" {
  description = "Cluster connection information"
  value = {
    fe_count           = var.fe_count
    be_count           = var.be_count
    fe_ips             = google_compute_instance_from_template.fe_instances[*].network_interface[0].access_config[0].nat_ip
    fe_internal_ips    = google_compute_instance_from_template.fe_instances[*].network_interface[0].network_ip
    lb_internal_ip     = google_compute_forwarding_rule.fe_forwarding_rule.ip_address
    ssh_user           = var.ssh_user
    fe_port            = "9030"
    be_port            = "9050"
  }
}

output "storage_info" {
  description = "Storage configuration details"
  value = {
    hot_storage_type       = var.hot_storage_type
    hot_storage_size       = var.hot_storage_size
    hot_storage_path       = "/opt/doris/be/storage"
    cold_storage_bucket    = google_storage_bucket.doris_cold_storage.name
    cold_storage_path      = "gs://${google_storage_bucket.doris_cold_storage.name}/doris-data"
    retention_days         = var.cold_storage_retention_days
  }
}

output "scaling_info" {
  description = "Auto scaling configuration"
  value = {
    be_min_count       = var.be_min_count
    be_max_count       = var.be_max_count
    current_count      = var.be_count
    cpu_target         = var.autoscaling_cpu_target
    scale_up_cooldown  = var.autoscaling_scale_up_cooldown
    scale_down_cooldown = var.autoscaling_scale_down_cooldown
  }
}

output "persistent_disks" {
  description = "Persistent disk names (survive instance termination)"
  value = {
    fe_meta_disks     = google_compute_disk.fe_meta_disk[*].name
    be_storage_disks  = google_compute_disk.be_storage_disk[*].name
  }
}

output "service_account" {
  description = "Service account for BE instances"
  value       = google_service_account.doris_be.email
}

output "terraform_state" {
  description = "Terraform state file location"
  value       = "terraform.tfstate"
}

output "deployment_commands" {
  description = "Useful deployment and management commands"
  value = {
    deploy_dev   = "terraform apply -var-file=terraform.tfvars.dev"
    deploy_sit   = "terraform apply -var-file=terraform.tfvars.sit"
    deploy_uat   = "terraform apply -var-file=terraform.tfvars.uat"
    deploy_prod  = "terraform apply -var-file=terraform.tfvars.prod"
    destroy      = "terraform destroy -var-file=<environment>"
    scale        = "gcloud compute instance-groups managed set-size <igm-name> --size=<count> --region=<region>"
    status       = "gcloud compute instance-groups managed list-instances <igm-name> --region=<region>"
  }
}

output "sql_examples" {
  description = "Example SQL commands for storage separation"
  value = {
    create_table_with_policy = "CREATE TABLE example (id INT, data STRING) PROPERTIES ('storage_policy' = 'hot_to_cold');"
    show_storage_policy      = "SHOW STORAGE POLICY;"
    show_data_distribution   = "SHOW DATA SKEW;"
    alter_table_policy       = "ALTER TABLE example SET ('storage_policy' = 'hot_to_cold');"
  }
}

output "architecture_info" {
  description = "Architecture overview"
  value = {
    fe_ha_enabled = true
    fdb_enabled   = true
    storage_separation = true
    be_autoscaling = true
    description = "Doris cluster with FoundationDB for FE HA, GCS for cold storage, and auto-scaling BE"
  }
}
