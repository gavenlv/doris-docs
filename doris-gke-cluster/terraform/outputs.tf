# ==========================================
# Doris GKE Cluster - Terraform Outputs
# ==========================================

# ==========================================
# GKE Cluster Information
# ==========================================
output "cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.doris_gke.name
}

output "cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = google_container_cluster.doris_gke.endpoint
}

output "cluster_ca_certificate" {
  description = "GKE cluster CA certificate"
  value       = google_container_cluster.doris_gke.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_region" {
  description = "GKE cluster region"
  value       = var.region
}

output "cluster_zone" {
  description = "GKE cluster zone"
  value       = var.zone
}

# ==========================================
# Network Information
# ==========================================
output "vpc_name" {
  description = "VPC network name"
  value       = google_compute_network.vpc.name
}

output "subnet_name" {
  description = "Subnet name"
  value       = google_compute_subnetwork.subnet.name
}

output "subnet_cidr" {
  description = "Subnet CIDR range"
  value       = google_compute_subnetwork.subnet.ip_cidr_range
}

# ==========================================
# Node Pool Information
# ==========================================
output "core_pool_name" {
  description = "Core node pool name"
  value       = google_container_node_pool.core_pool.name
}

output "be_core_pool_name" {
  description = "BE core node pool name"
  value       = google_container_node_pool.be_core_pool.name
}

output "be_compute_pool_name" {
  description = "BE compute node pool name"
  value       = google_container_node_pool.be_compute_pool.name
}

# ==========================================
# Storage Information
# ==========================================
output "gcs_bucket_name" {
  description = "GCS bucket name for cold storage"
  value       = google_storage_bucket.cold_storage.name
}

output "gcs_bucket_url" {
  description = "GCS bucket URL"
  value       = google_storage_bucket.cold_storage.url
}

# ==========================================
# Service Account Information
# ==========================================
output "doris_service_account_email" {
  description = "Doris service account email"
  value       = google_service_account.doris_sa.email
}

# ==========================================
# Kubectl Configuration
# ==========================================
output "kubeconfig_command" {
  description = "Command to configure kubectl"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.doris_gke.name} --region ${var.region} --project ${var.project_id}"
}

# ==========================================
# Connection Information
# ==========================================
output "connection_info" {
  description = "Cluster connection information"
  value = <<-EOT
    
    Doris GKE Cluster deployed successfully!
    
    Cluster Name: ${google_container_cluster.doris_gke.name}
    Region: ${var.region}
    
    Node Pools:
    - Core Pool (FE/FDB): ${var.core_pool_min_nodes}-${var.core_pool_max_nodes} nodes
    - BE Core Pool: ${var.be_core_pool_min_nodes}-${var.be_core_pool_max_nodes} nodes  
    - BE Compute Pool (Spot): ${var.be_compute_pool_min_nodes}-${var.be_compute_pool_max_nodes} nodes
    
    Storage:
    - Hot Storage: Local SSD (${var.hot_storage_size_gb}GB per BE node)
    - Cold Storage: GCS Bucket ${google_storage_bucket.cold_storage.name}
    
    To configure kubectl:
    $ gcloud container clusters get-credentials ${google_container_cluster.doris_gke.name} --region ${var.region} --project ${var.project_id}
    
    To deploy Doris components:
    $ cd kubernetes
    $ kubectl apply -f namespace.yaml
    $ kubectl apply -f doris-operator/
    $ kubectl apply -f doris-cluster/
    
  EOT
}
