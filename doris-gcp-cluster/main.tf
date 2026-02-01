terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

locals {
  cluster_name = "${var.cluster_name}-${var.environment}"
}

# ============================================================
# Network Configuration
# ============================================================

resource "google_compute_network" "doris_network" {
  name = "${local.cluster_name}-network"
}

resource "google_compute_subnetwork" "doris_subnet" {
  name          = "${local.cluster_name}-subnet"
  ip_cidr_range = var.subnet_cidr
  network       = google_compute_network.doris_network.id
  region        = var.region
}

resource "google_compute_firewall" "allow_internal" {
  name    = "${local.cluster_name}-allow-internal"
  network = google_compute_network.doris_network.id

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [var.subnet_cidr]
}

resource "google_compute_firewall" "allow_external" {
  name    = "${local.cluster_name}-allow-external"
  network = google_compute_network.doris_network.id

  allow {
    protocol = "tcp"
    ports    = ["9030", "9031", "9032", "8030", "8031", "8032", "9010", "9011", "9012"]
  }

  source_ranges = var.allowed_source_ranges
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "${local.cluster_name}-allow-ssh"
  network = google_compute_network.doris_network.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.allowed_source_ranges
}

resource "google_compute_firewall" "allow_health_check" {
  name    = "${local.cluster_name}-allow-health-check"
  network = google_compute_network.doris_network.id

  allow {
    protocol = "tcp"
    ports    = ["9030"]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
}

# ============================================================
# GCS Storage (Cold Storage for Compute-Storage Separation)
# ============================================================

resource "google_storage_bucket" "doris_cold_storage" {
  count         = var.enable_compute_storage_separation ? 1 : 0
  name          = var.gcs_bucket_name
  location      = var.region
  force_destroy = false
  uniform_bucket_level_access = true

  lifecycle_rule {
    condition {
      age = var.cold_storage_retention_days
    }
    action {
      type = "Delete"
    }
  }

  versioning {
    enabled = false
  }

  labels = {
    environment = var.environment
    cluster     = var.cluster_name
    purpose     = "doris-cold-storage"
  }
}

# ============================================================
# Persistent Disks (Survive instance termination)
# ============================================================

resource "google_compute_disk" "fe_meta_disk" {
  count = var.fe_count

  name  = "${local.cluster_name}-fe-${count.index + 1}-meta-disk"
  type  = var.fe_disk_type
  size  = var.fe_disk_size
  zone  = var.zone

  labels = {
    environment = var.environment
    cluster     = var.cluster_name
    component   = "fe-meta"
    instance_id = count.index + 1
  }
}

resource "google_compute_disk" "be_storage_disk" {
  count = var.enable_compute_storage_separation ? var.be_max_count : var.be_count

  name  = "${local.cluster_name}-be-${count.index + 1}-storage-disk"
  type  = var.hot_storage_type
  size  = var.hot_storage_size
  zone  = var.zone

  labels = {
    environment = var.environment
    cluster     = var.cluster_name
    component   = "be-storage"
    instance_id = count.index + 1
  }
}

# ============================================================
# FE Instance Template and Instances
# ============================================================

resource "google_compute_instance_template" "fe_template" {
  name_prefix  = "${local.cluster_name}-fe-"
  machine_type = var.fe_machine_type
  region       = var.region

  tags = ["doris-fe", local.cluster_name, "fe-health-check"]

  boot_disk {
    initialize_params {
      image = var.image_family
      size  = 50
      type  = "pd-balanced"
    }
  }

  attached_disk {
    source      = google_compute_disk.fe_meta_disk[0].id
    device_name = "fe-meta"
  }

  network_interface {
    subnetwork = google_compute_subnetwork.doris_subnet.id
    access_config {
      network_tier = "PREMIUM"
    }
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${file(var.ssh_public_key_path)}"
    user-data = templatefile("${path.module}/user-data-fe.sh", {
      cluster_name       = var.cluster_name
      environment        = var.environment
      fe_servers        = var.fe_servers
      fe_id             = "${count.index + 1}"
      gcs_bucket        = var.enable_compute_storage_separation ? var.gcs_bucket_name : ""
    })
  }

  scheduling {
    preemptible = var.fe_preemptible
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_instance_from_template" "fe_instances" {
  count           = var.fe_count
  name            = "${local.cluster_name}-fe-${count.index + 1}"
  source_template = google_compute_instance_template.fe_template.id
  zone            = var.zone

  # Attach persistent disk dynamically
  attached_disk {
    source      = google_compute_disk.fe_meta_disk[count.index].id
    device_name = "fe-meta"
  }
}

# ============================================================
# BE Instance Template
# ============================================================

resource "google_compute_instance_template" "be_template" {
  name_prefix  = "${local.cluster_name}-be-"
  machine_type = var.be_machine_type
  region       = var.region

  tags = ["doris-be", local.cluster_name]

  boot_disk {
    initialize_params {
      image = var.image_family
      size  = 50
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.doris_subnet.id
    access_config {
      network_tier = "PREMIUM"
    }
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${file(var.ssh_public_key_path)}"
    user-data = templatefile("${path.module}/user-data-be.sh", {
      cluster_name       = var.cluster_name
      environment        = var.environment
      fe_servers         = var.fe_servers
      be_id              = "0"
      gcs_bucket        = var.enable_compute_storage_separation ? var.gcs_bucket_name : ""
      enable_separation  = var.enable_compute_storage_separation
    })
  }

  scheduling {
    preemptible = var.be_preemptible
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================
# BE Instance Group Manager and Auto Scaling
# ============================================================

resource "google_compute_region_instance_group_manager" "be_igm" {
  count   = var.enable_autoscaling ? 1 : 0
  name    = "${local.cluster_name}-be-igm"
  region  = var.region
  version {
    instance_template = google_compute_instance_template.be_template.id
  }

  base_instance_name = "${local.cluster_name}-be"
  target_size       = var.be_count

  named_port {
    name = "http"
    port = 8040
  }

  named_port {
    name = "heartbeat"
    port = 9050
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.be_health_check[0].id
    initial_delay_sec = 300
  }

  update_policy {
    type           = "PROACTIVE"
    minimal_action = "REPLACE"
    max_surge_fixed = 1
    max_unavailable_fixed = 1
  }
}

resource "google_compute_region_autoscaler" "be_autoscaler" {
  count  = var.enable_autoscaling ? 1 : 0
  name   = "${local.cluster_name}-be-autoscaler"
  region = var.region
  target = google_compute_region_instance_group_manager.be_igm[0].id

  autoscaling_policy {
    min_replicas    = var.be_min_count
    max_replicas    = var.be_max_count
    cooldown_period = 60

    cpu_utilization {
      target = var.autoscaling_cpu_target
    }
  }
}

resource "google_compute_health_check" "be_health_check" {
  count = var.enable_autoscaling ? 1 : 0
  name  = "${local.cluster_name}-be-health-check"

  check_interval_sec  = 30
  timeout_sec         = 10
  healthy_threshold   = 2
  unhealthy_threshold = 3

  tcp_health_check {
    port = 9050
  }
}

# Fallback: Static BE instances when autoscaling is disabled
resource "google_compute_instance_from_template" "be_instances" {
  count           = var.enable_autoscaling ? 0 : var.be_count
  name            = "${local.cluster_name}-be-${count.index + 1}"
  source_template = google_compute_instance_template.be_template.id
  zone            = var.zone

  attached_disk {
    source      = google_compute_disk.be_storage_disk[count.index].id
    device_name = "be-storage"
  }
}

# ============================================================
# Internal Load Balancer for FE
# ============================================================

resource "google_compute_region_health_check" "fe_health_check" {
  count   = var.enable_load_balancer ? 1 : 0
  name    = "${local.cluster_name}-fe-health-check"
  region  = var.region

  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  tcp_health_check {
    port = 9030
  }
}

resource "google_compute_region_instance_group" "fe_ig" {
  count   = var.enable_load_balancer ? 1 : 0
  name    = "${local.cluster_name}-fe-ig"
  region  = var.region
  zone    = var.zone

  instances = google_compute_instance_from_template.fe_instances[*].self_link

  named_port {
    name = "mysql"
    port = 9030
  }

  named_port {
    name = "http"
    port = 8030
  }
}

resource "google_compute_region_backend_service" "fe_backend" {
  count                 = var.enable_load_balancer ? 1 : 0
  name                  = "${local.cluster_name}-fe-backend"
  region                = var.region
  load_balancing_scheme = "INTERNAL"

  health_checks = [google_compute_region_health_check.fe_health_check[0].id]

  backend {
    group = google_compute_region_instance_group.fe_ig[0].id
  }

  protocol = "TCP"
}

resource "google_compute_forwarding_rule" "fe_forwarding_rule" {
  count                  = var.enable_load_balancer ? 1 : 0
  name                   = "${local.cluster_name}-fe-forwarding-rule"
  region                 = var.region
  load_balancing_scheme = "INTERNAL"
  all_ports              = true
  backend_service        = google_compute_region_backend_service.fe_backend[0].id
  subnetwork             = google_compute_subnetwork.doris_subnet.id
  network                = google_compute_network.doris_network.id
}

# ============================================================
# Outputs
# ============================================================

output "fe_ips" {
  description = "FE instance public IPs"
  value       = google_compute_instance_from_template.fe_instances[*].network_interface[0].access_config[0].nat_ip
}

output "be_ips" {
  description = "BE instance public IPs (if autoscaling disabled)"
  value       = var.enable_autoscaling ? [] : google_compute_instance_from_template.be_instances[*].network_interface[0].access_config[0].nat_ip
}

output "fe_internal_ips" {
  description = "FE instance internal IPs"
  value       = google_compute_instance_from_template.fe_instances[*].network_interface[0].network_ip
}

output "lb_internal_ip" {
  description = "Internal Load Balancer IP"
  value       = var.enable_load_balancer ? google_compute_forwarding_rule.fe_forwarding_rule[0].ip_address : null
}

output "gcs_bucket" {
  description = "GCS bucket name for cold storage"
  value       = var.enable_compute_storage_separation ? var.gcs_bucket_name : null
}

output "persistent_disks" {
  description = "Persistent disk names (survive instance termination)"
  value = {
    fe_meta_disks  = google_compute_disk.fe_meta_disk[*].name
    be_storage_disks = google_compute_disk.be_storage_disk[*].name
  }
}

output "cluster_info" {
  description = "Cluster connection information"
  value = {
    fe_count           = var.fe_count
    be_count           = var.be_count
    be_min_count       = var.be_min_count
    be_max_count       = var.be_max_count
    enable_autoscaling = var.enable_autoscaling
    enable_lb          = var.enable_load_balancer
    enable_separation  = var.enable_compute_storage_separation
    fe_port            = "9030"
    be_port            = "9050"
  }
}
