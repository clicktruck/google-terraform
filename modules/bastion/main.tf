data "google_compute_image" "latest_custom_image" {
  filter      = "name eq '^${var.os_image}.*'"
  most_recent = true
}


resource "google_compute_instance" "vm" {
  name           = var.vm_name
  machine_type   = var.machine_type
  zone           = var.zone
  can_ip_forward = true

  scheduling {
    preemptible       = var.scheduling_preemptible
    automatic_restart = var.scheduling_automaticrestart
  }

  boot_disk {
    auto_delete = true
    initialize_params {
      image = data.google_compute_image.latest_custom_image.self_link
      type  = "pd-ssd"
      size  = "80"
    }
  }

  network_interface {
    network    = var.vm_network
    subnetwork = var.vm_subnetwork # empty string if no subnet

    # if assigning internal IP
    #network_ip = cidrhost("<a.b.c.d/xx>",<lastOctet>)

    # using dynamic block to optionally include
    # access_config, which provides ephem ext IP
    #access_config {
    #  // empty block means ephemeral external IP
    #}
    dynamic "access_config" {
      for_each = var.has_public_ip ? [1] : []
      content {}
    }

  }


  // using ssh key at project level
  metadata = {
    enable-oslogin : "false" # false=allow ssh from project level metadata
  }


  service_account {
    # leaving email empty means default compute engine service account will be used
    #email = ""
    # leaving scopes empty means we need to use service account to reach gcloud api on vm, it will not use default compute engine account
    scopes = var.vm_scopes
  }


  // Apply the firewall rule to allow external IPs to access this instance
  tags = var.vm_network_tags
}