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
  network  = google_compute_network.doris_network.id

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
  network  = google_compute_network.doris_network.id

  allow {
    protocol = "tcp"
    ports    = ["9030", "9031", "9032", "8030", "8031", "8032", "9010", "9011", "9012"]
  }

  source_ranges = var.allowed_source_ranges
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "${local.cluster_name}-allow-ssh"
  network  = google_compute_network.doris_network.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.allowed_source_ranges
}

resource "google_compute_instance_template" "fe_template" {
  name_prefix  = "${local.cluster_name}-fe-"
  machine_type = var.fe_machine_type
  region       = var.region

  tags = ["doris-fe", local.cluster_name]

  boot_disk {
    initialize_params {
      image  = var.image_family
      labels = {}
      size   = var.fe_disk_size
      type   = var.fe_disk_type
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
      cluster_name = var.cluster_name
      fe_servers  = var.fe_servers
      fe_id       = "${count.index + 1}"
    })
  }

  scheduling {
    preemptible = var.fe_preemptible
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_instance_template" "be_template" {
  name_prefix  = "${local.cluster_name}-be-"
  machine_type = var.be_machine_type
  region       = var.region

  tags = ["doris-be", local.cluster_name]

  boot_disk {
    initialize_params {
      image  = var.image_family
      labels = {}
      size   = var.be_disk_size
      type   = var.be_disk_type
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
      cluster_name = var.cluster_name
      fe_servers  = var.fe_servers
      be_id       = "${count.index + 1}"
    })
  }

  scheduling {
    preemptible = var.be_preemptible
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
}

resource "google_compute_instance_from_template" "be_instances" {
  count           = var.be_count
  name            = "${local.cluster_name}-be-${count.index + 1}"
  source_template = google_compute_instance_template.be_template.id
  zone            = var.zone
}

output "fe_ips" {
  description = "FE instance public IPs"
  value       = google_compute_instance_from_template.fe_instances[*].network_interface[0].access_config[0].nat_ip
}

output "be_ips" {
  description = "BE instance public IPs"
  value       = google_compute_instance_from_template.be_instances[*].network_interface[0].access_config[0].nat_ip
}

output "fe_internal_ips" {
  description = "FE instance internal IPs"
  value       = google_compute_instance_from_template.fe_instances[*].network_interface[0].network_ip
}

output "be_internal_ips" {
  description = "BE instance internal IPs"
  value       = google_compute_instance_from_template.be_instances[*].network_interface[0].network_ip
}

output "cluster_info" {
  description = "Cluster connection information"
  value = {
    fe_count = var.fe_count
    be_count = var.be_count
    fe_port  = "9030"
    be_port  = "9050"
  }
}
