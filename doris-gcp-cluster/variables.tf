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

# ============================================================
# High-Performance Configuration
# ============================================================

variable "enable_high_performance" {
  description = "Enable high-performance mode with optimized settings"
  type        = bool
  default     = false
}

variable "enable_local_ssd" {
  description = "Use Local SSD for BE storage (NVMe, 375GB each)"
  type        = bool
  default     = false
}

variable "local_ssd_count" {
  description = "Number of Local SSDs per BE instance (max 8)"
  type        = number
  default     = 1
  validation {
    condition     = var.local_ssd_count >= 1 && var.local_ssd_count <= 8
    error_message = "Local SSD count must be between 1 and 8."
  }
}

variable "enable_preemptible_be_pool" {
  description = "Enable separate preemptible BE pool for cost optimization"
  type        = bool
  default     = false
}

variable "preemptible_be_count" {
  description = "Number of preemptible BE instances"
  type        = number
  default     = 0
}

variable "preemptible_be_machine_type" {
  description = "Machine type for preemptible BE instances"
  type        = string
  default     = "c2-standard-30"
}

variable "enable_time_based_scaling" {
  description = "Enable time-based auto scaling"
  type        = bool
  default     = false
}

variable "busy_hours_start" {
  description = "Start time for busy hours (HH:MM format)"
  type        = string
  default     = "08:00"
}

variable "busy_hours_end" {
  description = "End time for busy hours (HH:MM format)"
  type        = string
  default     = "22:00"
}

variable "busy_hours_be_count" {
  description = "BE count during busy hours"
  type        = number
  default     = 15
}

variable "off_hours_be_count" {
  description = "BE count during off hours"
  type        = number
  default     = 5
}

# ============================================================
# BE Performance Tuning Variables
# ============================================================

variable "be_memory_limit" {
  description = "BE process memory limit"
  type        = string
  default     = "80%"
}

variable "be_query_memory_limit" {
  description = "BE query memory limit per query"
  type        = string
  default     = "50GB"
}

variable "be_storage_page_cache_limit" {
  description = "BE storage page cache limit"
  type        = string
  default     = "20GB"
}

variable "be_scan_thread_pool_thread_num" {
  description = "BE scan thread pool size"
  type        = number
  default     = 48
}

variable "be_fragment_pool_thread_num_max" {
  description = "BE fragment pool max thread count"
  type        = number
  default     = 128
}

variable "be_compaction_thread_num" {
  description = "BE compaction thread count"
  type        = number
  default     = 16
}

# ============================================================
# FE Performance Tuning Variables
# ============================================================

variable "fe_query_timeout" {
  description = "FE query timeout in seconds"
  type        = number
  default     = 300
}

variable "fe_max_running_query_num" {
  description = "FE max running query number"
  type        = number
  default     = 100
}

variable "fe_query_cache_capacity" {
  description = "FE query cache capacity"
  type        = string
  default     = "10GB"
}

# ============================================================
# Import Optimization Variables
# ============================================================

variable "streaming_load_max_mb" {
  description = "Max size in MB for streaming load"
  type        = number
  default     = 10240
}

variable "streaming_load_rpc_max_alive_time_sec" {
  description = "Max alive time in seconds for streaming load RPC"
  type        = number
  default     = 1200
}

variable "max_send_batch_parallelism_per_job" {
  description = "Max send batch parallelism per job"
  type        = number
  default     = 10
}

# ============================================================
# Monitoring Configuration
# ============================================================

variable "enable_monitoring" {
  description = "Enable Prometheus/Grafana monitoring"
  type        = bool
  default     = true
}

variable "log_level" {
  description = "Log level (INFO, WARN, ERROR, DEBUG)"
  type        = string
  default     = "INFO"
}

variable "audit_log_enabled" {
  description = "Enable audit logging"
  type        = bool
  default     = true
}
