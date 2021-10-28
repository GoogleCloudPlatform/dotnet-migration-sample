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

variable "project_id" {
  description = "Name of the project ID"
}

variable "region" {
  description = "Name of the region"
}

variable "network" {
  description = "Name of the VPC network"
}

variable "private_ip" {
  description = "Name of the private IP address name for cloud sql"
}

variable "zones" {
  type        = list(string)
  description = "The zones to host the resources in (minimum of 2)"
}

variable "network_vpc_subnet1" {
  description = "Name of the VPC subnetwork 1"
}

variable "network_vpc_subnet1_ip_range" {
  description = "RFC1918 IP range for VPC in CIDR format eg. 192.168.0.0/21"
}

variable "network_vpc_subnet_gke_pods" {
  description = "Name of the VPC subnetwork for GKE pods"
}

variable "network_vpc_subnet_gke_pods_ip_range" {
  description = "RFC1918 IP range for VPC in CIDR format eg. 192.168.4.0/21" # minimum of /21 to /8
}

variable "network_vpc_subnet_gke_services" {
  description = "Name of the VPC subnetwork for GKE services"
}

variable "network_vpc_subnet_gke_services_ip_range" {
  description = "RFC1918 IP range for VPC in CIDR format eg. 192.168.8.0/21" # minimum of /21 to /8
}

variable "name" {
  description = "Name of the resource"
}

variable "fw_name" {
  description = "Name of the firewall resource"
}

variable "fw_source_range" {
  description = "allowed source IP address for firewall in CIDR format including [] eg. [1.2.3.4/32]"
}
