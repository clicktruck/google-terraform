terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.26.0"
    }
    random = {
      source = "hashicorp/random"
    }
  }
  required_version = ">= 0.14"
}
