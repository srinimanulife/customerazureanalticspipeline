# Azure Active Directory Groups for RBAC

# Data Engineers Group - Full access to all data platform resources
resource "azuread_group" "data_engineers" {
  display_name     = "${var.project_name}-${var.aad_group_data_engineers}"
  security_enabled = true
  description      = "Data engineers with full access to data platform"
}

# Data Analysts Group - Read access to curated data and Synapse
resource "azuread_group" "data_analysts" {
  display_name     = "${var.project_name}-${var.aad_group_data_analysts}"
  security_enabled = true
  description      = "Data analysts with read access to gold layer and Synapse"
}

# Platform Admins Group - Infrastructure management
resource "azuread_group" "admins" {
  display_name     = "${var.project_name}-${var.aad_group_admins}"
  security_enabled = true
  description      = "Platform administrators with full infrastructure access"
}

# Role Assignments - Storage Account

# Data Engineers: Storage Blob Data Contributor on all containers
resource "azurerm_role_assignment" "engineers_storage_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_group.data_engineers.object_id
}

# Data Analysts: Storage Blob Data Reader on gold container only
resource "azurerm_role_assignment" "analysts_storage_reader" {
  scope                = "${azurerm_storage_account.main.id}/blobServices/default/containers/${azurerm_storage_container.gold.name}"
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azuread_group.data_analysts.object_id
}

# Admins: Owner on resource group
resource "azurerm_role_assignment" "admins_rg_owner" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Owner"
  principal_id         = azuread_group.admins.object_id
}

# Role Assignments - Databricks

# Data Engineers: Contributor on Databricks workspace
resource "azurerm_role_assignment" "engineers_databricks_contributor" {
  scope                = azurerm_databricks_workspace.main.id
  role_definition_name = "Contributor"
  principal_id         = azuread_group.data_engineers.object_id
}

# Role Assignments - Synapse

# Data Engineers: Synapse Administrator
resource "azurerm_synapse_role_assignment" "engineers_synapse_admin" {
  synapse_workspace_id = azurerm_synapse_workspace.main.id
  role_name            = "Synapse Administrator"
  principal_id         = azuread_group.data_engineers.object_id
}

# Data Analysts: Synapse SQL User
resource "azurerm_synapse_role_assignment" "analysts_synapse_sql_user" {
  synapse_workspace_id = azurerm_synapse_workspace.main.id
  role_name            = "Synapse SQL User"
  principal_id         = azuread_group.data_analysts.object_id
}

# Role Assignments - Data Factory

# Data Engineers: Data Factory Contributor
resource "azurerm_role_assignment" "engineers_adf_contributor" {
  scope                = azurerm_data_factory.main.id
  role_definition_name = "Data Factory Contributor"
  principal_id         = azuread_group.data_engineers.object_id
}

# Data Analysts: Reader on Data Factory (can view but not edit pipelines)
resource "azurerm_role_assignment" "analysts_adf_reader" {
  scope                = azurerm_data_factory.main.id
  role_definition_name = "Reader"
  principal_id         = azuread_group.data_analysts.object_id
}
