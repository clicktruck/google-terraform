# network
data "google_compute_network" "vpc" {
  name = var.vpc_network_name
}

# subnetwork
data "google_compute_subnetwork" "subnet" {
  name   = var.vpc_subnetwork_name
  region = var.region
}

# pubsub topic for upgrade notifications
# https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_topic
resource "google_pubsub_topic" "cluster_topic" {
  name                       = "${var.cluster_name}-${var.vpc_subnetwork_name}"
  message_retention_duration = "86600s"
}

# available cluster versions
data "google_container_engine_versions" "cluster_versions" {
  location       = var.region
  version_prefix = var.cluster_version_prefix
}

# https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/container_cluster
resource "google_container_cluster" "apcluster" {
  provider = google-beta
  name     = var.cluster_name
  # Autopilot clusters are always regional (never zonal)
  location = var.region

  # makes this an Autopilot cluster
  enable_autopilot = true

  delete_protection = false

  min_master_version = data.google_container_engine_versions.cluster_versions.latest_master_version

  release_channel {
    channel = var.cluster_release_channel
  }

  network    = data.google_compute_network.vpc.name
  subnetwork = data.google_compute_subnetwork.subnet.name

  # worker nodes with private IP addresses
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block_28
    master_global_access_config {
      enabled = true
    }
  }

  notification_config {
    pubsub {
      enabled = true
      topic   = google_pubsub_topic.cluster_topic.id
    }
  }

  # if this block exists at all, the "control plane for auth networks" will be enabled, but have no networks
  # so we need nested dynamic to represent
  # --no-enable-master-authorized-networks
  dynamic "master_authorized_networks_config" {
    for_each = length(var.master_authorized_networks_cidr_list) > 0 ? [1] : []
    content {

      # dynamic inner block to list authorized networks
      dynamic "cidr_blocks" {
        for_each = var.master_authorized_networks_cidr_list
        # notice the name inside is not 'each', it is name of dynamic block
        content {
          cidr_block   = cidr_blocks.value
          display_name = "authnetworks ${cidr_blocks.value}"
        }
      } # end dynamic cidr_blocks

    } # end content of master_authorized_networks_config

  } # end dynamic block master_authorized_networks_config

  # added so that 'tf apply' does not continually find update changes
  vertical_pod_autoscaling {
    enabled = true
  }

  addons_config {
    # wanted by ASM
    http_load_balancing {
      disabled = false
    }

    # beta, enabled
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
  }

  maintenance_policy {
    recurring_window {
      start_time = "2022-01-28T10:00:00Z" # UTC
      end_time   = "2022-01-28T14:00:00Z" # UTC
      recurrence = "FREQ=WEEKLY;BYDAY=TU,WE,TH,FR,SA,SU"
    }
  }

  # ignore master version being auto-upgraded
  lifecycle {
    ignore_changes = [
      min_master_version
    ]
  }

  # references names of secondary ranges
  # this enables ip aliasing '--enable-ip-alias'
  ip_allocation_policy {
    services_secondary_range_name = var.secondary_range_services_name
    cluster_secondary_range_name  = var.secondary_range_pods_name
  }

}

resource "google_compute_ssl_policy" "ssl-policy" {
  name            = "${var.cluster_name}-ssl-policy"
  profile         = "MODERN"
  min_tls_version = "TLS_1_2"
}

resource "google_compute_security_policy" "security-policy" {
  name     = "${var.cluster_name}-security-policy"
  provider = google-beta

  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable = true
    }
  }

  rule {
    action   = "deny(403)"
    priority = "1000"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('xss-stable')"
      }
    }
    description = "XSS attack filtering"
  }
  rule {
    action   = "deny(403)"
    priority = "1001"
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('sqli-stable')"
      }
    }
    description = "SQL injection attack filtering"
  }
  rule {
    action   = "deny(403)"
    priority = "1002"
    match {
      expr {
        expression = "origin.region_code == 'RU'"
      }
    }
    description = "RU country block, test using www.locabrowser.com"
  }

  rule {
    action   = "allow"
    priority = "2147483647"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "default rule that must exist"
  }
}

# Register the cluster, makes viewable in 'Anthos' section
# https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/gke_hub_membership
# https://cloud.google.com/anthos/multicluster-management/connect/registering-a-cluster#register_cluster
resource "google_gke_hub_membership" "membership" {
  membership_id = google_container_cluster.apcluster.name
  endpoint {
    gke_cluster {
      resource_link = google_container_cluster.apcluster.id
    }
  }
  authority {
    issuer = "https://container.googleapis.com/v1/${google_container_cluster.apcluster.id}"
  }
}

resource "null_resource" "write_kubeconfig" {
  # creates local kubeconfig file
  provisioner "local-exec" {
    command = <<EOT
      gcloud container clusters get-credentials ${var.cluster_name} --region=${var.region}
EOT
    environment = {
      "KUBECONFIG" = "kubeconfig-${var.cluster_name}"
    }
    working_dir = pathexpand(var.kubeconfig_directory)
    on_failure  = continue
  }

  depends_on = [google_container_cluster.apcluster]
}

resource "null_resource" "destroy_kubeconfig" {
  triggers = {
    "name"                 = var.cluster_name
    "kubeconfig_directory" = var.kubeconfig_directory
  }
  # deletes local kubeconfig file
  provisioner "local-exec" {
    when = destroy
    # does not have access to var, only self's attributes
    command     = "rm -f kubeconfig-${self.triggers.name}"
    working_dir = pathexpand(self.triggers.kubeconfig_directory)
    on_failure  = continue
  }

  depends_on = [google_container_cluster.apcluster]
}