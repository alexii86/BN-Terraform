terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.30.0"
    }
  }
}

provider "google" {
  credentials     = "account.json" ## create service account from GCP Console and download JSON key
  project         = "bordernet"
  region          = var.region
  request_timeout = "10m"
}

data "google_compute_zones" "available_zones" {}

# # Create a Virtual Network
resource "google_compute_network" "mgmt_network" {
  name                    = "bn-mgmt-network"
  auto_create_subnetworks = "false"

}

resource "google_compute_network" "public_network" {
  name                    = "bn-public-network"
  auto_create_subnetworks = "false"

}

resource "google_compute_network" "private_network" {
  name                    = "bn-private-network"
  auto_create_subnetworks = "false"

}

resource "google_compute_subnetwork" "mgmt" {
  name          = "bn-mgmt"
  ip_cidr_range = var.mgmt_prefix
  region        = var.region
  network       = google_compute_network.mgmt_network.id
}

resource "google_compute_subnetwork" "public" {
  name          = "bn-public"
  ip_cidr_range = var.public_prefix
  region        = var.region
  network       = google_compute_network.public_network.id
}

resource "google_compute_subnetwork" "private" {
  name          = "bn-private"
  ip_cidr_range = var.private_prefix
  region        = var.region
  network       = google_compute_network.private_network.id
}

resource "google_compute_firewall" "mgmt_default" {
  name    = "mgmt-firewall"
  network = google_compute_network.mgmt_network.id

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["22", "443", "8443"]
  }
  source_ranges = ["0.0.0.0/0"]

}

resource "google_compute_firewall" "public_default" {
  name    = "public-firewall"
  network = google_compute_network.public_network.id

  allow {
    protocol = "all"
  }
  source_ranges = ["0.0.0.0/0"]

}

resource "google_compute_firewall" "private_default" {
  name    = "private-firewall"
  network = google_compute_network.private_network.id

  allow {
    protocol = "all"
  }
  source_ranges = ["0.0.0.0/0"]

}


resource "google_compute_address" "bn-pip" {
  name = "bn-pip"
}

resource "google_compute_address" "ems-pip" {
  name = "ems-pip"
}


resource "google_compute_image" "bn_os_image" {
  name = "bn-os-image"

  raw_disk {
    source = var.bn_os_disk
  }
  guest_os_features {
    type = "MULTI_IP_SUBNET"
  }
  guest_os_features {
    type = "UEFI_COMPATIBLE"
  }
}

resource "google_compute_image" "bn_data_image" {
  name = "bn-data-image"
  timeouts {
    create = "10m"
  }

  raw_disk {
    source = var.bn_data_disk
  }
  guest_os_features {
    type = "MULTI_IP_SUBNET"
  }
}

resource "google_compute_image" "ems_os_image" {
  name = "ems-os-image"

  raw_disk {
    source = var.ems_os_disk
  }
  guest_os_features {
    type = "MULTI_IP_SUBNET"
  }
  guest_os_features {
    type = "UEFI_COMPATIBLE"
  }
}

resource "google_compute_image" "ems_data_image" {
  name = "ems-data-image"
  timeouts {
    create = "10m"
  }

  raw_disk {
    source = var.ems_data_disk
  }
  guest_os_features {
    type = "MULTI_IP_SUBNET"
  }
}

resource "google_compute_disk" "bn_os_disk" {
  name                      = "bn-os-disk"
  type                      = "pd-ssd"
  zone                      = data.google_compute_zones.available_zones.names[0]
  image                     = google_compute_image.bn_os_image.id
  physical_block_size_bytes = 4096
}

resource "google_compute_disk" "bn_data_disk" {
  name                      = "bn-data-disk"
  type                      = "pd-ssd"
  zone                      = data.google_compute_zones.available_zones.names[0]
  image                     = google_compute_image.bn_data_image.id
  physical_block_size_bytes = 4096
}

resource "google_compute_disk" "ems_os_disk" {
  name                      = "ems-os-disk"
  type                      = "pd-ssd"
  zone                      = data.google_compute_zones.available_zones.names[0]
  image                     = google_compute_image.ems_os_image.id
  physical_block_size_bytes = 4096
}

resource "google_compute_disk" "ems_data_disk" {
  name                      = "ems-data-disk"
  type                      = "pd-ssd"
  zone                      = data.google_compute_zones.available_zones.names[0]
  image                     = google_compute_image.ems_data_image.id
  physical_block_size_bytes = 4096
}

resource "google_compute_instance" "bn1" {
  name         = "bn1"
  machine_type = var.bn_vm_size
  zone         = data.google_compute_zones.available_zones.names[0]

  boot_disk {
    source = google_compute_disk.bn_os_disk.id
  }
  attached_disk {
    source = google_compute_disk.bn_data_disk.id
  }
  network_interface {
    subnetwork = google_compute_subnetwork.mgmt.id
    access_config {
      nat_ip = google_compute_address.bn-pip.address
    }
  }
  network_interface {
    subnetwork = google_compute_subnetwork.public.id
  }
  network_interface {
    subnetwork = google_compute_subnetwork.private.id
  }
}

resource "google_compute_instance" "ems" {
  name         = "ems"
  machine_type = var.ems_vm_size
  zone         = data.google_compute_zones.available_zones.names[0]

  boot_disk {
    source = google_compute_disk.ems_os_disk.id
  }
  attached_disk {
    source = google_compute_disk.ems_data_disk.id
  }
  network_interface {
    subnetwork = google_compute_subnetwork.mgmt.id
    access_config {
      nat_ip = google_compute_address.ems-pip.address
    }
  }
}


output "MGMT_url" {
  value = "https://${google_compute_address.bn-pip.address}/"
}

output "EMS_url" {
  value = "https://${google_compute_address.ems-pip.address}:8443"
}

output "Public_ip_address" {
  value = google_compute_instance.bn1.network_interface.1.network_ip
}

output "Private_ip_address" {
  value = google_compute_instance.bn1.network_interface.2.network_ip
}