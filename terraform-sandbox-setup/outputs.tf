/**
 * Copyright 2018 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

output "instances_self_links" {
  description = "List of self-links for compute instances"
  value       = google_compute_instance.compute_instance.*.self_link
}

output "instances_details" {
  description = "List of all details for compute instances"
  value       = google_compute_instance.compute_instance.*
  sensitive   = true
}

output "firewall_details" {
  description = "List of all details for instance firewall"
  value       = google_compute_firewall.firewall_win_rdp.*
  sensitive   = true
}

output "gke_details" {
  description = "List of all details for container instances"
  value       = google_container_cluster.gke_windows.*
  sensitive   = true
}

output "gke_windows_nodepool_details" {
  description = "List of all details for container instances"
  value       = google_container_node_pool.windows_nodepool.*
  sensitive   = true
}

output "database_self_links" {
  description = "List of self-links for cloudsql instances"
  value       = google_sql_database_instance.db_instance.*.self_link
}

output "database_details" {
  description = "List of all details for cloudsql instances"
  value       = google_sql_database_instance.db_instance.*
  sensitive   = true
}
