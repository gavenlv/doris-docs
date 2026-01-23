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
