# ==========================================
# Doris GKE Cluster - Terraform Variables
# ==========================================
# Version: 1.0
# Last Updated: 2026-02-26

# ==========================================
# GCP Project Configuration
# ==========================================
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

# ==========================================
# Cluster Configuration
# ==========================================
variable "cluster_name" {
  description = "GKE cluster name"
  type        = string
  default     = "doris-gke-cluster"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "kubernetes_version" {
  description = "Kubernetes version for GKE cluster"
  type        = string
  default     = "1.28"
}

# ==========================================
# Network Configuration
# ==========================================
variable "network_name" {
  description = "VPC network name"
  type        = string
  default     = "doris-vpc"
}

variable "subnet_name" {
  description = "Subnet name"
  type        = string
  default     = "doris-subnet"
}

variable "subnet_cidr" {
  description = "Subnet CIDR range"
  type        = string
  default     = "10.0.0.0/16"
}

variable "pods_cidr" {
  description = "Secondary CIDR range for pods"
  type        = string
  default     = "10.1.0.0/16"
}

variable "services_cidr" {
  description = "Secondary CIDR range for services"
  type        = string
  default     = "10.2.0.0/16"
}

variable "master_cidr" {
  description = "CIDR range for GKE master (Private Cluster)"
  type        = string
  default     = "172.16.0.0/28"
}

# ==========================================
# Node Pool Configuration
# ==========================================
# Core Node Pool (FE/FDB)
variable "core_pool_machine_type" {
  description = "Machine type for core node pool"
  type        = string
  default     = "n2-standard-4"
}

variable "core_pool_min_nodes" {
  description = "Minimum number of nodes in core pool"
  type        = number
  default     = 3
}

variable "core_pool_max_nodes" {
  description = "Maximum number of nodes in core pool"
  type        = number
  default     = 5
}

variable "core_pool_disk_size" {
  description = "Disk size for core nodes (GB)"
  type        = number
  default     = 100
}

# BE Core Pool
variable "be_core_pool_machine_type" {
  description = "Machine type for BE core node pool"
  type        = string
  default     = "n2-standard-16"
}

variable "be_core_pool_min_nodes" {
  description = "Minimum number of BE core nodes"
  type        = number
  default     = 2
}

variable "be_core_pool_max_nodes" {
  description = "Maximum number of BE core nodes"
  type        = number
  default     = 3
}

# BE Compute Pool (Spot)
variable "be_compute_pool_machine_type" {
  description = "Machine type for BE compute node pool"
  type        = string
  default     = "n2-standard-16"
}

variable "be_compute_pool_min_nodes" {
  description = "Minimum number of BE compute nodes"
  type        = number
  default     = 2
}

variable "be_compute_pool_max_nodes" {
  description = "Maximum number of BE compute nodes"
  type        = number
  default     = 20
}

variable "be_compute_pool_spot" {
  description = "Use Spot VMs for BE compute pool"
  type        = bool
  default     = true
}

# ==========================================
# Storage Configuration
# ==========================================
variable "gcs_bucket_name" {
  description = "GCS bucket name for cold storage"
  type        = string
}

variable "hot_storage_size_gb" {
  description = "Local SSD size per BE node (GB)"
  type        = number
  default     = 1500  # 1.5TB
}

variable "cold_storage_retention_days" {
  description = "Cold storage retention days"
  type        = number
  default     = 3
}

# ==========================================
# Private Cluster Configuration
# ==========================================
variable "enable_private_cluster" {
  description = "Enable private GKE cluster"
  type        = bool
  default     = true
}

variable "enable_private_endpoint" {
  description = "Enable private endpoint for GKE master"
  type        = bool
  default     = true
}

variable "enable_private_google_access" {
  description = "Enable Private Google Access for GCS"
  type        = bool
  default     = true
}

variable "master_authorized_networks" {
  description = "List of CIDR blocks that can access GKE master"
  type        = list(object({
    cidr_block   = string
    display_name = string
  }))
  default     = []
}

# ==========================================
# Image Registry Configuration
# ==========================================
variable "nexus_url" {
  description = "Nexus Docker registry URL"
  type        = string
  default     = "nexus.company.com"
}

variable "use_nexus" {
  description = "Use Nexus as Docker registry"
  type        = bool
  default     = true
}

# ==========================================
# Monitoring Configuration
# ==========================================
variable "enable_monitoring" {
  description = "Enable monitoring components"
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "Enable Cloud Logging"
  type        = bool
  default     = true
}
