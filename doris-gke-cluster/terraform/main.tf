# ==========================================
# Doris GKE Cluster - Main Terraform Configuration
# ==========================================
# Version: 1.0
# Last Updated: 2026-02-26
# Description: Deploy Doris on GKE with Private Cluster

# ==========================================
# Providers
# ==========================================
terraform {
  required_version = ">= 1.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    bucket = "doris-terraform-state"
    prefix = "doris-gke-cluster"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# ==========================================
# VPC Network
# ==========================================
resource "google_compute_network" "vpc" {
  name                    = var.network_name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  description = "VPC for Doris GKE Cluster (${var.environment})"
}

# Subnet
resource "google_compute_subnetwork" "subnet" {
  name          = var.subnet_name
  network       = google_compute_network.vpc.name
  region        = var.region
  ip_cidr_range = var.subnet_cidr

  # Secondary ranges for GKE
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }

  # Enable Private Google Access for GCS
  private_ip_google_access = var.enable_private_google_access

  description = "Subnet for Doris GKE Cluster (${var.environment})"
}

# Cloud NAT (for internet access during initial setup)
resource "google_compute_router" "router" {
  name    = "${var.cluster_name}-router"
  network = google_compute_network.vpc.name
  region  = var.region
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.cluster_name}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  # Only for initial setup, can be disabled later
  min_ports_per_vm = 64
}

# ==========================================
# GKE Cluster
# ==========================================
resource "google_container_cluster" "doris_gke" {
  name     = var.cluster_name
  location = var.region

  # Kubernetes version
  min_master_version = var.kubernetes_version

  # Network configuration
  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name

  # IP allocation policy
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Private Cluster configuration
  private_cluster_config {
    enable_private_nodes    = var.enable_private_cluster
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_cidr
  }

  # Master authorized networks (for access from specific IPs)
  dynamic "master_authorized_networks_config" {
    for_each = length(var.master_authorized_networks) > 0 ? [1] : []
    content {
      dynamic "cidr_blocks" {
        for_each = var.master_authorized_networks
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = cidr_blocks.value.display_name
        }
      }
    }
  }

  # Disable default node pool (we'll create custom node pools)
  remove_default_node_pool = true
  initial_node_count       = 1

  # Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Monitoring and logging
  monitoring_config {
    enable_components = var.enable_monitoring ? ["SYSTEM_COMPONENTS", "WORKLOADS"] : []
  }

  logging_config {
    enable_components = var.enable_logging ? ["SYSTEM_COMPONENTS", "WORKLOADS"] : []
  }

  # Maintenance window
  maintenance_policy {
    recurring_window {
      start_time = "2024-01-01T00:00:00Z"
      end_time   = "2024-01-01T04:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SU"
    }
  }

  # Cluster autoscaling (for node pools)
  cluster_autoscaling {
    enabled = false  # We'll manage autoscaling at node pool level
  }

  # Resource labels
  resource_labels = {
    environment = var.environment
    managed_by  = "terraform"
    project     = "doris-gke"
  }

  # Deletion protection
  deletion_protection = false

  # Timeout
  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}

# ==========================================
# Node Pools
# ==========================================

# Core Node Pool (for FE/FDB)
resource "google_container_node_pool" "core_pool" {
  name     = "core-pool"
  cluster  = google_container_cluster.doris_gke.name
  location = var.region

  # Node count
  initial_node_count = var.core_pool_min_nodes
  autoscaling {
    min_node_count = var.core_pool_min_nodes
    max_node_count = var.core_pool_max_nodes
  }

  # Machine configuration
  node_config {
    machine_type = var.core_pool_machine_type
    disk_size_gb = var.core_pool_disk_size
    disk_type    = "pd-ssd"

    # OAuth scopes
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    # Labels
    labels = {
      environment = var.environment
      pool        = "core"
      role        = "fe-fdb"
    }

    # Taints (optional - for dedicated FE/FDB nodes)
    # taint {
    #   key    = "dedicated"
    #   value  = "core"
    #   effect = "NO_SCHEDULE"
    # }
  }

  # Management
  management {
    auto_repair  = true
    auto_upgrade = true
  }

  # Upgrade settings
  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  timeouts {
    create = "20m"
    update = "20m"
    delete = "20m"
  }
}

# BE Core Node Pool (non-Spot, baseline capacity)
resource "google_container_node_pool" "be_core_pool" {
  name     = "be-core-pool"
  cluster  = google_container_cluster.doris_gke.name
  location = var.region

  initial_node_count = var.be_core_pool_min_nodes
  autoscaling {
    min_node_count = var.be_core_pool_min_nodes
    max_node_count = var.be_core_pool_max_nodes
  }

  node_config {
    machine_type = var.be_core_pool_machine_type
    
    # Local SSD for hot data (4 x 375GB = 1.5TB)
    local_ssd_count = 4
    
    disk_size_gb = 100
    disk_type    = "pd-ssd"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = {
      environment = var.environment
      pool        = "be-core"
      role        = "be"
      storage     = "local-ssd"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  timeouts {
    create = "20m"
    update = "20m"
    delete = "20m"
  }
}

# BE Compute Node Pool (Spot VMs for elastic scaling)
resource "google_container_node_pool" "be_compute_pool" {
  name     = "be-compute-pool"
  cluster  = google_container_cluster.doris_gke.name
  location = var.region

  initial_node_count = var.be_compute_pool_min_nodes
  autoscaling {
    min_node_count = var.be_compute_pool_min_nodes
    max_node_count = var.be_compute_pool_max_nodes
  }

  node_config {
    machine_type = var.be_compute_pool_machine_type
    
    # Local SSD for hot data (4 x 375GB = 1.5TB)
    local_ssd_count = 4
    
    disk_size_gb = 100
    disk_type    = "pd-ssd"

    # Spot VM configuration
    spot = var.be_compute_pool_spot

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = {
      environment = var.environment
      pool        = "be-compute"
      role        = "be"
      storage     = "local-ssd"
      spot        = "true"
    }

    # Taint to prevent critical workloads on Spot nodes
    taint {
      key    = "spot"
      value  = "true"
      effect = "NO_SCHEDULE"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 2
    max_unavailable = 1
  }

  timeouts {
    create = "20m"
    update = "20m"
    delete = "20m"
  }
}

# ==========================================
# GCS Bucket for Cold Storage
# ==========================================
resource "google_storage_bucket" "cold_storage" {
  name          = var.gcs_bucket_name
  location      = var.region
  force_destroy = false

  # Storage class
  storage_class = "STANDARD"

  # Versioning
  versioning {
    enabled = false
  }

  # Lifecycle policy
  lifecycle_rule {
    condition {
      age = var.cold_storage_retention_days
    }
    action {
      type = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = 90  # 90 days
    }
    action {
      type = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  # Uniform bucket-level access
  uniform_bucket_level_access = true

  # Labels
  labels = {
    environment = var.environment
    managed_by  = "terraform"
    purpose     = "doris-cold-storage"
  }
}

# ==========================================
# IAM Service Account for Doris
# ==========================================
resource "google_service_account" "doris_sa" {
  account_id   = "doris-${var.environment}"
  display_name = "Doris Service Account (${var.environment})"
  description  = "Service account for Doris components"
  project      = var.project_id
}

# Grant GCS access
resource "google_storage_bucket_iam_member" "doris_gcs_access" {
  bucket = google_storage_bucket.cold_storage.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.doris_sa.email}"
}
