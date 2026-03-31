# ---------------------------------------------------------------------------
# Resource Locks — prevent accidental deletion of critical storage
# Toggle via: storage_protect_critical = true
# Must be removed before teardown/destroy.
# ---------------------------------------------------------------------------

resource "azurerm_management_lock" "tfstate" {
  count      = var.storage_protect_critical ? 1 : 0
  name       = "lock-tfstate"
  scope      = azurerm_storage_account.tfstate.id
  lock_level = "CanNotDelete"
  notes      = "Protects Terraform state. Remove before destroy: storage_protect_critical = false"
}

resource "azurerm_management_lock" "velero_backup" {
  count      = var.storage_protect_critical && var.velero_enabled ? 1 : 0
  name       = "lock-velero-backup"
  scope      = azurerm_storage_account.velero_backup[0].id
  lock_level = "CanNotDelete"
  notes      = "Protects Velero backup data. Remove before destroy: storage_protect_critical = false"
}
