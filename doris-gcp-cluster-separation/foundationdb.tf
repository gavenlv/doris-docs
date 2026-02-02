# ============================================================
# FoundationDB Cluster for Doris FE High Availability
# ============================================================
# FoundationDB 作为 Doris FE 的分布式元数据存储后端
# 提供强一致性、高可用、水平扩展的元数据存储能力

locals {
  fdb_cluster_name = "${local.cluster_name}-fdb"
  fdb_version      = "7.3.27"
}

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

# FoundationDB 实例模板
resource "google_compute_instance_template" "fdb_template" {
  name_prefix  = "${local.fdb_cluster_name}-"
  machine_type = var.fdb_machine_type
  region       = var.region

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

  network_interface {
    subnetwork = google_compute_subnetwork.doris_subnet.id
    access_config {
      network_tier = "PREMIUM"
    }
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${file(var.ssh_public_key_path)}"
    user-data = templatefile("${path.module}/user-data-fdb.sh", {
      cluster_name    = local.fdb_cluster_name
      fdb_version     = local.fdb_version
      fdb_id          = "${count.index + 1}"
      fdb_count       = var.fdb_count
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

# FoundationDB 实例
resource "google_compute_instance_from_template" "fdb_instances" {
  count           = var.fdb_count
  name            = "${local.fdb_cluster_name}-${count.index + 1}"
  source_template = google_compute_instance_template.fdb_template.id
  zone            = var.zone

  network_interface {
    subnetwork = google_compute_subnetwork.doris_subnet.id
    access_config {
      network_tier = "PREMIUM"
    }
  }

  attached_disk {
    source      = google_compute_disk.fdb_data_disk[count.index].id
    device_name = "fdb-data"
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

# FoundationDB 负载均衡器 (用于 FE 连接)
resource "google_compute_address" "fdb_internal_ip" {
  name         = "${local.fdb_cluster_name}-ip"
  subnetwork   = google_compute_subnetwork.doris_subnet.id
  address_type = "INTERNAL"
  region       = var.region
}

resource "google_compute_region_backend_service" "fdb_backend" {
  name                  = "${local.fdb_cluster_name}-backend"
  region                = var.region
  load_balancing_scheme = "INTERNAL"

  health_checks = [google_compute_health_check.fdb_health_check.id]

  dynamic "backend" {
    for_each = google_compute_instance_from_template.fdb_instances
    content {
      group = backend.value.self_link
    }
  }

  protocol = "TCP"
}

resource "google_compute_forwarding_rule" "fdb_forwarding_rule" {
  name                   = "${local.fdb_cluster_name}-forwarding-rule"
  region                 = var.region
  load_balancing_scheme = "INTERNAL"
  ports                  = ["4500"]
  backend_service        = google_compute_region_backend_service.fdb_backend.id
  subnetwork             = google_compute_subnetwork.doris_subnet.id
  network                = google_compute_network.doris_network.id
  ip_address             = google_compute_address.fdb_internal_ip.address
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

# FoundationDB 集群配置 Secret (存储在 GCP Secret Manager)
resource "google_secret_manager_secret" "fdb_cluster_file" {
  secret_id = "${local.fdb_cluster_name}-cluster-file"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "fdb_cluster_file_version" {
  secret = google_secret_manager_secret.fdb_cluster_file.id

  secret_data = <<-EOT
    ${local.fdb_cluster_name}:${join(",", [for i in range(var.fdb_count) : "10.0.0.${100 + i + 1}:4500"])}
  EOT

  depends_on = [google_compute_instance_from_template.fdb_instances]
}

# 允许 FE 服务账号访问 FDB Secret
resource "google_secret_manager_secret_iam_member" "fe_fdb_secret_access" {
  secret_id = google_secret_manager_secret.fdb_cluster_file.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.doris_fe.email}"
}

# Doris FE 服务账号
resource "google_service_account" "doris_fe" {
  account_id   = "${local.cluster_name}-fe-sa"
  display_name = "Doris FE Service Account"
}

# 输出 FoundationDB 信息
output "foundationdb_info" {
  description = "FoundationDB cluster information"
  value = {
    cluster_name    = local.fdb_cluster_name
    version         = local.fdb_version
    instance_count  = var.fdb_count
    internal_ip     = google_compute_address.fdb_internal_ip.address
    coordinator_list = join(",", [for i in range(var.fdb_count) : "10.0.0.${100 + i + 1}:4500"])
    cluster_file_secret = google_secret_manager_secret.fdb_cluster_file.secret_id
  }
}

output "fdb_instance_ips" {
  description = "FoundationDB instance IPs"
  value       = google_compute_instance_from_template.fdb_instances[*].network_interface[0].network_ip
}
