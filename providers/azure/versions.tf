terraform {
  required_version = ">= 1.7.0"

  required_providers {
    azurerm    = { source = "hashicorp/azurerm", version = "4.68.0" }
    azuread    = { source = "hashicorp/azuread", version = "3.8.0" }
    http       = { source = "hashicorp/http", version = "3.5.0" }
    random     = { source = "hashicorp/random", version = "3.8.1" }
    time       = { source = "hashicorp/time", version = "0.13.1" }
    helm       = { source = "hashicorp/helm", version = "2.17.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "2.38.0" }
  }
}
