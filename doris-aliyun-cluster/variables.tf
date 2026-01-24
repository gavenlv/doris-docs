variable "access_key" {
  description = "Aliyun Access Key ID"
  type        = string
  sensitive   = true
}

variable "secret_key" {
  description = "Aliyun Access Key Secret"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Aliyun Region"
  type        = string
  default     = "cn-hangzhou"
}

variable "zone" {
  description = "Aliyun Zone"
  type        = string
  default     = "cn-hangzhou-i"
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

variable "vpc_cidr" {
  description = "VPC CIDR range"
  type        = string
  default     = "172.16.0.0/16"
}

variable "vswitch_cidr" {
  description = "VSwitch CIDR range"
  type        = string
  default     = "172.16.0.0/24"
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

variable "fe_instance_type" {
  description = "FE instance type"
  type        = string
  default     = "ecs.g6.large"
}

variable "be_instance_type" {
  description = "BE instance type"
  type        = string
  default     = "ecs.g6.2xlarge"
}

variable "fe_disk_size" {
  description = "FE system disk size in GB"
  type        = number
  default     = 50
}

variable "be_disk_size" {
  description = "BE system disk size in GB"
  type        = number
  default     = 100
}

variable "fe_disk_category" {
  description = "FE disk category"
  type        = string
  default     = "cloud_essd"
}

variable "be_disk_category" {
  description = "BE disk category"
  type        = string
  default     = "cloud_essd"
}

variable "image_id" {
  description = "ECS image ID"
  type        = string
  default     = "ubuntu_22_04_x64_20G_alibase_20231225.vhd"
}

variable "internet_bandwidth" {
  description = "Internet bandwidth in Mbps"
  type        = number
  default     = 5
}

variable "fe_spot_strategy" {
  description = "FE spot instance strategy (SpotWithPriceLimit, SpotAsPriceGo)"
  type        = string
  default     = "SpotWithPriceLimit"
}

variable "be_spot_strategy" {
  description = "BE spot instance strategy (SpotWithPriceLimit, SpotAsPriceGo)"
  type        = string
  default     = "SpotWithPriceLimit"
}

variable "fe_servers" {
  description = "FE servers configuration"
  type        = string
  default     = "fe1:172.16.0.11:9010"
}

variable "enable_tiered_storage" {
  description = "Enable tiered storage (SSD hot, OSS warm, OSS cold)"
  type        = bool
  default     = false
}

variable "hot_storage_size" {
  description = "Hot storage size in GB (SSD)"
  type        = number
  default     = 100
}

variable "warm_storage_size" {
  description = "Warm storage size in GB (OSS Standard)"
  type        = number
  default     = 500
}

variable "cold_storage_size" {
  description = "Cold storage size in GB (OSS Archive)"
  type        = number
  default     = 1000
}

variable "oss_bucket_prefix" {
  description = "OSS bucket prefix"
  type        = string
  default     = "doris"
}

variable "oss_hot_bucket_name" {
  description = "OSS hot bucket name (for SSD hot storage)"
  type        = string
  default     = ""
}

variable "oss_warm_bucket_name" {
  description = "OSS warm bucket name (for warm storage)"
  type        = string
  default     = ""
}

variable "oss_cold_bucket_name" {
  description = "OSS cold bucket name (for cold storage)"
  type        = string
  default     = ""
}

variable "oss_access_key_id" {
  description = "OSS Access Key ID for tiered storage"
  type        = string
  sensitive   = true
  default     = ""
}

variable "oss_access_key_secret" {
  description = "OSS Access Key Secret for tiered storage"
  type        = string
  sensitive   = true
  default     = ""
}

variable "oss_endpoint" {
  description = "OSS endpoint (e.g., oss-cn-hangzhou.aliyuncs.com)"
  type        = string
  default     = "oss-cn-hangzhou.aliyuncs.com"
}
