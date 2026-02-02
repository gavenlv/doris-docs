# ============================================================
# GCS Bucket for Installation Artifacts (Private Network)
# ============================================================
# 所有安装包存储在此 Bucket，VM 通过内网访问

locals {
  artifacts_bucket_name = "${var.gcs_bucket_name}-artifacts"
}

# 安装包存储 Bucket (与集群同区域)
resource "google_storage_bucket" "artifacts" {
  name          = local.artifacts_bucket_name
  location      = var.region
  force_destroy = false
  uniform_bucket_level_access = true

  # 内网访问配置
  public_access_prevention = "enforced"

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 5
    }
    action {
      type = "Delete"
    }
  }

  labels = {
    environment = var.environment
    cluster     = var.cluster_name
    purpose     = "doris-artifacts"
    network     = "private"
  }
}

# 允许 VPC 内网访问 Bucket
resource "google_storage_bucket_iam_member" "artifacts_vpc_access" {
  bucket = google_storage_bucket.artifacts.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.doris_fe.email}"
}

resource "google_storage_bucket_iam_member" "artifacts_be_access" {
  bucket = google_storage_bucket.artifacts.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.doris_be.email}"
}

resource "google_storage_bucket_iam_member" "artifacts_fdb_access" {
  bucket = google_storage_bucket.artifacts.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.foundationdb.email}"
}

# 输出 Artifact Bucket 信息
output "artifacts_bucket" {
  description = "GCS bucket for installation artifacts"
  value = {
    name   = google_storage_bucket.artifacts.name
    url    = "gs://${google_storage_bucket.artifacts.name}"
    region = var.region
  }
}

output "required_artifacts" {
  description = "List of required installation artifacts"
  value = {
    doris = {
      fe_package = "apache-doris-fe-4.0.2-bin-x86_64.tar.gz"
      be_package = "apache-doris-be-4.0.2-bin-x86_64.tar.gz"
    }
    foundationdb = {
      client_deb = "foundationdb-clients_7.3.27-1_amd64.deb"
      server_deb = "foundationdb-server_7.3.27-1_amd64.deb"
    }
    gcsfuse = {
      package = "gcsfuse_latest_amd64.deb"
    }
  }
}
