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

locals {
  fw_protocol             = "TCP"
  fw_ports                = ["3389"]
  num_instances           = 1
  machine_type            = "e2-standard-4"
  disk_image_compute      = "injae-sandbox/contosouniversity-lab"
  disk_size_gb_compute    = 80
  disk_size_gb_containers = 40
  disk_type_containers    = "pd-balanced"
  db_root_pw              = "P@55w0rd!"
  database_version        = "SQLSERVER_2017_EXPRESS"
  tier                    = "db-custom-2-3840"
}

################## HELPER RESOURCES ##################

resource "random_id" "randomchar" {
  byte_length = 2
}

################## HELPER RESOURCES ##################

###################
# Enable GCP APIs
##################

module "project-services" {
  source  = "terraform-google-modules/project-factory/google//modules/project_services"
  version = "10.1.1"

  project_id = var.project_id

  activate_apis = [
    "compute.googleapis.com",
    "iam.googleapis.com",
    "container.googleapis.com",
    "containerregistry.googleapis.com",
    "run.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "servicenetworking.googleapis.com",
    "sqladmin.googleapis.com"
  ]
}

################## NETWORK RESOURCES ##################

#############
# VPC
#############

resource "google_compute_network" "vpc_network" {
  project                 = var.project_id 
  name                    = "${var.network}-${random_id.randomchar.hex}"
  auto_create_subnetworks = false
}

# cloudsql private services access
resource "google_compute_global_address" "private_ip_address" {
  provider = google-beta
  project = var.project_id
  name          = var.private_ip
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 24
  network       = google_compute_network.vpc_network.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  provider = google-beta
  
  network                 = google_compute_network.vpc_network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

resource "google_compute_firewall" "firewall_win_rdp" {
  project = var.project_id
  name    = var.fw_name
  network = google_compute_network.vpc_network.name

  allow {
    protocol = local.fw_protocol
    ports    = local.fw_ports
  }

  source_ranges = [var.fw_source_range]
}

#############
# Subnets
#############

resource "google_compute_subnetwork" "subnet1" {
  project       = var.project_id
  name          = "${var.network_vpc_subnet1}-${random_id.randomchar.hex}"
  ip_cidr_range = var.network_vpc_subnet1_ip_range
  region        = var.region
  network       = google_compute_network.vpc_network.name
  secondary_ip_range = [
    {
      range_name    = var.network_vpc_subnet_gke_pods
      ip_cidr_range = var.network_vpc_subnet_gke_pods_ip_range
    },
    {
      range_name    = var.network_vpc_subnet_gke_services
      ip_cidr_range = var.network_vpc_subnet_gke_services_ip_range
    }
  ]
}

################## NETWORK RESOURCES ##################

################## COMPUTE RESOURCES ##################

#############
# GCE Sandbox
#############


resource "google_compute_instance" "compute_instance" {
  provider     = google
  count        = local.num_instances
  name         = "${var.name}-${random_id.randomchar.hex}"
  machine_type = local.machine_type
  project      = var.project_id
  zone         = var.zones[0]
  tags         = [var.fw_name]

  boot_disk {
    initialize_params {
      size  = local.disk_size_gb_compute
      image = local.disk_image_compute
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet1.self_link
    access_config {}
  }

  service_account {
    # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
    scopes = ["cloud-platform"]
  }

  deletion_protection = false
}

#####################
# Kubernetes cluster
#####################

resource "google_container_cluster" "gke_windows" {
  project         = var.project_id
  location        = var.region
  name            = "${var.name}-${random_id.randomchar.hex}"
  network         = google_compute_network.vpc_network.self_link
  subnetwork      = google_compute_subnetwork.subnet1.self_link
  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = var.network_vpc_subnet_gke_pods
    services_secondary_range_name = var.network_vpc_subnet_gke_services
  }
  remove_default_node_pool = false # Windows node pool needs a linux pool
  initial_node_count       = 1
  release_channel {
    channel = "REGULAR"
  }

}

resource "google_container_node_pool" "windows_nodepool" {
  project            = var.project_id
  cluster            = google_container_cluster.gke_windows.id
  location           = var.region
  name               = "${var.name}-windows-node-pool"
  node_locations     = var.zones
  initial_node_count = 1
  node_config {
    machine_type = local.machine_type
    disk_size_gb = local.disk_size_gb_containers
    disk_type    = local.disk_type_containers
    image_type   = "WINDOWS_LTSC"
    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/devstorage.read_only"

    ]
  }
  timeouts {
    create = "60m"
  }
}

################## COMPUTE RESOURCES ##################

################## DATABASE RESOURCES ##################

#############
# DB Instances
#############

resource "google_sql_database_instance" "db_instance" {
  project          = var.project_id
  name             = "${var.name}-${random_id.randomchar.hex}"
  database_version = local.database_version
  region           = var.region
  root_password    = local.db_root_pw

  settings {
    tier = local.tier

    ip_configuration {
      ipv4_enabled = false
      private_network = google_compute_network.vpc_network.id

      authorized_networks {
        name  = "allowed-${var.fw_source_range}"
        value = var.fw_source_range
      }
    }
  }

  deletion_protection = false
  depends_on = [google_service_networking_connection.private_vpc_connection]
}

################## DATABASE RESOURCES ##################