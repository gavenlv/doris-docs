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
