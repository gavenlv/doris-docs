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
  # FoundationDB cluster configuration
  fdb_cluster_name = "${var.cluster_name}-fdb-${var.environment}"
  fdb_version      = "7.3.27"
}

# ============================================================
# Private Network Configuration (No Internet Access)
# ============================================================

resource "google_compute_network" "doris_network" {
  name                    = "${local.cluster_name}-network"
  auto_create_subnetworks = false
  # 创建私有网络，不自动创建子网
}

resource "google_compute_subnetwork" "doris_subnet" {
  name          = "${local.cluster_name}-subnet"
  ip_cidr_range = var.subnet_cidr
  network       = google_compute_network.doris_network.id
  region        = var.region
  
  # 配置私有 Google 访问（允许访问 GCS 等 Google API）
  private_ip_google_access = true
  
  # 配置 VPC Flow Logs
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# 创建 Cloud NAT（仅用于出站访问 Google API，如 GCS）
resource "google_compute_router" "router" {
  count   = var.enable_nat ? 1 : 0
  name    = "${local.cluster_name}-router"
  region  = var.region
  network = google_compute_network.doris_network.id
}

resource "google_compute_router_nat" "nat" {
  count                              = var.enable_nat ? 1 : 0
  name                               = "${local.cluster_name}-nat"
  router                             = google_compute_router.router[0].name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
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

# GCS Bucket IAM for BE instances
resource "google_storage_bucket_iam_member" "be_storage_access" {
  bucket = google_storage_bucket.doris_cold_storage.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.doris_be.email}"
}

# Service Account for BE instances
resource "google_service_account" "doris_be" {
  account_id   = "${local.cluster_name}-be-sa"
  display_name = "Doris BE Service Account"
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
  count = var.be_max_count

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
# FoundationDB Cluster for FE High Availability
# ============================================================

# FoundationDB 服务账号
resource "google_service_account" "foundationdb" {
  account_id   = "${local.cluster_name}-fdb-sa"
  display_name = "FoundationDB Service Account"
}

# FoundationDB 持久化磁盘
resource "google_compute_disk" "fdb_data_disk" {
  count = var.fdb_count

  name  = "${local.fdb_cluster_name}-${count.index + 1}-data"
  type  = "pd-ssd"
  size  = var.fdb_disk_size
  zone  = var.zone

  labels = {
    environment = var.environment
    cluster     = var.cluster_name
    component   = "foundationdb"
    instance_id = count.index + 1
  }
}

# FoundationDB 实例
resource "google_compute_instance" "fdb_instances" {
  count        = var.fdb_count
  name         = "${local.fdb_cluster_name}-${count.index + 1}"
  machine_type = var.fdb_machine_type
  zone         = var.zone

  tags = ["foundationdb", local.cluster_name, "fdb-cluster"]

  service_account {
    email  = google_service_account.foundationdb.email
    scopes = ["cloud-platform"]
  }

  boot_disk {
    initialize_params {
      image = var.image_family
      size  = 50
      type  = "pd-balanced"
    }
  }

  attached_disk {
    source      = google_compute_disk.fdb_data_disk[count.index].id
    device_name = "fdb-data"
  }

  network_interface {
    subnetwork = google_compute_subnetwork.doris_subnet.id
    access_config {
      network_tier = "PREMIUM"
    }
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${file(var.ssh_public_key_path)}"
    user-data = templatefile("${path.module}/user-data-fdb.sh", {
      cluster_name     = local.fdb_cluster_name
      fdb_version      = local.fdb_version
      fdb_id           = count.index + 1
      fdb_count        = var.fdb_count
      fdb_coordinators = join(",", [for i in range(var.fdb_count) : "foundationdb@10.0.0.${100 + i + 1}:4500"])
    })
  }

  scheduling {
    preemptible = false
  }

  lifecycle {
    create_before_destroy = true
  }
}

# FoundationDB 防火墙规则
resource "google_compute_firewall" "allow_fdb" {
  name    = "${local.cluster_name}-allow-fdb"
  network = google_compute_network.doris_network.id

  allow {
    protocol = "tcp"
    ports    = ["4500", "4501", "4502", "4503"]
  }

  source_ranges = [var.subnet_cidr]
  target_tags   = ["foundationdb"]
}

# FoundationDB 负载均衡器
resource "google_compute_address" "fdb_internal_ip" {
  name         = "${local.fdb_cluster_name}-ip"
  subnetwork   = google_compute_subnetwork.doris_subnet.id
  address_type = "INTERNAL"
  region       = var.region
}

resource "google_compute_health_check" "fdb_health_check" {
  name = "${local.fdb_cluster_name}-health-check"

  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  tcp_health_check {
    port = 4500
  }
}

resource "google_compute_region_backend_service" "fdb_backend" {
  name                  = "${local.fdb_cluster_name}-backend"
  region                = var.region
  load_balancing_scheme = "INTERNAL"

  health_checks = [google_compute_health_check.fdb_health_check.id]

  dynamic "backend" {
    for_each = google_compute_instance.fdb_instances
    content {
      group = backend.value.self_link
    }
  }

  protocol = "TCP"
}

resource "google_compute_forwarding_rule" "fdb_forwarding_rule" {
  name                  = "${local.fdb_cluster_name}-forwarding-rule"
  region                = var.region
  load_balancing_scheme = "INTERNAL"
  ports                 = ["4500"]
  backend_service       = google_compute_region_backend_service.fdb_backend.id
  subnetwork            = google_compute_subnetwork.doris_subnet.id
  network               = google_compute_network.doris_network.id
  ip_address            = google_compute_address.fdb_internal_ip.address
}

# ============================================================
# FE Instance Template and Instances (with FDB support)
# ============================================================

resource "google_service_account" "doris_fe" {
  account_id   = "${local.cluster_name}-fe-sa"
  display_name = "Doris FE Service Account"
}

resource "google_compute_instance_template" "fe_template" {
  name_prefix  = "${local.cluster_name}-fe-"
  machine_type = var.fe_machine_type
  region       = var.region

  tags = ["doris-fe", local.cluster_name, "fe-health-check"]

  service_account {
    email  = google_service_account.doris_fe.email
    scopes = ["cloud-platform"]
  }

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
    user-data = templatefile("${path.module}/user-data-fe.sh", {
      cluster_name       = var.cluster_name
      environment        = var.environment
      fe_servers        = var.fe_servers
      fe_id             = "${count.index + 1}"
      gcs_bucket        = var.gcs_bucket_name
      fdb_cluster_file  = "${local.fdb_cluster_name}:${join(",", [for i in range(var.fdb_count) : "10.0.0.${100 + i + 1}:4500"])}"
      fdb_enabled       = true
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

  attached_disk {
    source      = google_compute_disk.fe_meta_disk[count.index].id
    device_name = "fe-meta"
  }

  depends_on = [google_compute_instance.fdb_instances]
}

# ============================================================
# BE Instance Template with Storage Separation
# ============================================================

resource "google_compute_instance_template" "be_template" {
  name_prefix  = "${local.cluster_name}-be-"
  machine_type = var.be_machine_type
  region       = var.region

  tags = ["doris-be", local.cluster_name]

  service_account {
    email  = google_service_account.doris_be.email
    scopes = ["cloud-platform"]
  }

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
      gcs_bucket        = var.gcs_bucket_name
      hot_storage_path  = "/opt/doris/be/storage"
      cold_storage_path = "gs://${var.gcs_bucket_name}/doris-data"
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
    health_check      = google_compute_health_check.be_health_check.id
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
  name   = "${local.cluster_name}-be-autoscaler"
  region = var.region
  target = google_compute_region_instance_group_manager.be_igm.id

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
  name  = "${local.cluster_name}-be-health-check"

  check_interval_sec  = 30
  timeout_sec         = 10
  healthy_threshold   = 2
  unhealthy_threshold = 3

  tcp_health_check {
    port = 9050
  }
}

# ============================================================
# Internal Load Balancer for FE
# ============================================================

resource "google_compute_region_health_check" "fe_health_check" {
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
  name    = "${local.cluster_name}-fe-ig"
  region  = var.region

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
  name                  = "${local.cluster_name}-fe-backend"
  region                = var.region
  load_balancing_scheme = "INTERNAL"

  health_checks = [google_compute_region_health_check.fe_health_check.id]

  backend {
    group = google_compute_region_instance_group.fe_ig.id
  }

  protocol = "TCP"
}

resource "google_compute_forwarding_rule" "fe_forwarding_rule" {
  name                   = "${local.cluster_name}-fe-forwarding-rule"
  region                 = var.region
  load_balancing_scheme = "INTERNAL"
  all_ports              = true
  backend_service        = google_compute_region_backend_service.fe_backend.id
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

output "fe_internal_ips" {
  description = "FE instance internal IPs"
  value       = google_compute_instance_from_template.fe_instances[*].network_interface[0].network_ip
}

output "lb_internal_ip" {
  description = "Internal Load Balancer IP for Doris"
  value       = google_compute_forwarding_rule.fe_forwarding_rule.ip_address
}

output "gcs_bucket" {
  description = "GCS bucket name for cold storage"
  value       = google_storage_bucket.doris_cold_storage.name
}

output "gcs_bucket_url" {
  description = "GCS bucket URL"
  value       = "gs://${google_storage_bucket.doris_cold_storage.name}"
}

output "persistent_disks" {
  description = "Persistent disk names (survive instance termination)"
  value = {
    fe_meta_disks  = google_compute_disk.fe_meta_disk[*].name
    be_storage_disks = google_compute_disk.be_storage_disk[*].name
    fdb_data_disks = google_compute_disk.fdb_data_disk[*].name
  }
}

output "cluster_info" {
  description = "Cluster connection information"
  value = {
    fe_count           = var.fe_count
    be_count           = var.be_count
    be_min_count       = var.be_min_count
    be_max_count       = var.be_max_count
    fdb_count          = var.fdb_count
    enable_autoscaling = true
    enable_lb          = true
    enable_separation  = true
    enable_fdb         = true
    fe_port            = "9030"
    be_port            = "9050"
    gcs_bucket         = var.gcs_bucket_name
  }
}

output "storage_info" {
  description = "Storage configuration"
  value = {
    hot_storage_type  = var.hot_storage_type
    hot_storage_size  = var.hot_storage_size
    cold_storage_bucket = var.gcs_bucket_name
    cold_storage_retention = var.cold_storage_retention_days
  }
}

output "foundationdb_info" {
  description = "FoundationDB cluster information"
  value = {
    cluster_name     = local.fdb_cluster_name
    version          = local.fdb_version
    instance_count   = var.fdb_count
    internal_ip      = google_compute_address.fdb_internal_ip.address
    coordinator_list = join(",", [for i in range(var.fdb_count) : "10.0.0.${100 + i + 1}:4500"])
    instance_ips     = google_compute_instance.fdb_instances[*].network_interface[0].network_ip
  }
}
