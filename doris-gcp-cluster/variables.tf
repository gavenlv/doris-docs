variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP Zone"
  type        = string
  default     = "us-central1-a"
}

variable "cluster_name" {
  description = "Doris cluster name"
  type        = string
  default     = "doris"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "subnet_cidr" {
  description = "Subnet CIDR range"
  type        = string
  default     = "10.0.0.0/16"
}

variable "allowed_source_ranges" {
  description = "IP ranges allowed to access the cluster"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "fe_count" {
  description = "Number of FE instances"
  type        = number
  default     = 1
  validation {
    condition     = var.fe_count >= 1 && var.fe_count <= 3
    error_message = "FE count must be between 1 and 3."
  }
}

variable "be_count" {
  description = "Number of BE instances"
  type        = number
  default     = 2
  validation {
    condition     = var.be_count >= 2
    error_message = "BE count must be at least 2."
  }
}

variable "fe_machine_type" {
  description = "FE instance machine type"
  type        = string
  default     = "e2-medium"
}

variable "be_machine_type" {
  description = "BE instance machine type"
  type        = string
  default     = "e2-standard-2"
}

variable "fe_disk_size" {
  description = "FE boot disk size in GB"
  type        = number
  default     = 50
}

variable "be_disk_size" {
  description = "BE boot disk size in GB"
  type        = number
  default     = 100
}

variable "fe_disk_type" {
  description = "FE disk type"
  type        = string
  default     = "pd-balanced"
}

variable "be_disk_type" {
  description = "BE disk type"
  type        = string
  default     = "pd-ssd"
}

variable "image_family" {
  description = "Source image family"
  type        = string
  default     = "ubuntu-2204-lts"
}

variable "ssh_user" {
  description = "SSH username"
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key"
  type        = string
}

variable "fe_preemptible" {
  description = "Use preemptible instances for FE"
  type        = bool
  default     = false
}

variable "be_preemptible" {
  description = "Use preemptible instances for BE"
  type        = bool
  default     = false
}

variable "fe_servers" {
  description = "FE servers configuration"
  type        = string
  default     = "fe1:10.0.0.11:9010"
}

# Compute Storage Separation Configuration
variable "enable_compute_storage_separation" {
  description = "Enable compute-storage separation with GCS"
  type        = bool
  default     = false
}

variable "gcs_bucket_name" {
  description = "GCS bucket name for cold storage"
  type        = string
  default     = ""
}

variable "hot_storage_type" {
  description = "Hot storage disk type"
  type        = string
  default     = "pd-ssd"
}

variable "hot_storage_size" {
  description = "Hot storage disk size in GB"
  type        = number
  default     = 200
}

variable "cold_storage_retention_days" {
  description = "Cold data retention days in GCS"
  type        = number
  default     = 7
}

# Auto Scaling Configuration
variable "enable_autoscaling" {
  description = "Enable auto scaling for BE instances"
  type        = bool
  default     = false
}

variable "be_min_count" {
  description = "Minimum number of BE instances for auto scaling"
  type        = number
  default     = 2
}

variable "be_max_count" {
  description = "Maximum number of BE instances for auto scaling"
  type        = number
  default     = 5
}

variable "autoscaling_cpu_target" {
  description = "CPU utilization target for auto scaling (percentage)"
  type        = number
  default     = 70
}

variable "autoscaling_scale_up_cooldown" {
  description = "Cooldown period for scale up in seconds"
  type        = number
  default     = 300
}

variable "autoscaling_scale_down_cooldown" {
  description = "Cooldown period for scale down in seconds"
  type        = number
  default     = 300
}

# Load Balancer Configuration
variable "enable_load_balancer" {
  description = "Enable internal load balancer for FE"
  type        = bool
  default     = false
}
