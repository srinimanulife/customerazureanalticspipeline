output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_primary_endpoint" {
  description = "Primary blob endpoint"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "databricks_workspace_url" {
  description = "Databricks workspace URL"
  value       = azurerm_databricks_workspace.main.workspace_url
}

output "databricks_workspace_id" {
  description = "Databricks workspace ID"
  value       = azurerm_databricks_workspace.main.workspace_id
}

output "synapse_workspace_name" {
  description = "Synapse workspace name"
  value       = azurerm_synapse_workspace.main.name
}

output "synapse_sql_endpoint" {
  description = "Synapse SQL endpoint"
  value       = azurerm_synapse_workspace.main.connectivity_endpoints.sql
}

output "synapse_dev_endpoint" {
  description = "Synapse development endpoint"
  value       = azurerm_synapse_workspace.main.connectivity_endpoints.dev
}

output "data_factory_name" {
  description = "Data Factory name"
  value       = azurerm_data_factory.main.name
}

output "data_factory_id" {
  description = "Data Factory resource ID"
  value       = azurerm_data_factory.main.id
}

output "aad_group_engineers_id" {
  description = "AAD group ID for data engineers"
  value       = azuread_group.data_engineers.id
}

output "aad_group_analysts_id" {
  description = "AAD group ID for data analysts"
  value       = azuread_group.data_analysts.id
}

output "aad_group_admins_id" {
  description = "AAD group ID for admins"
  value       = azuread_group.admins.id
}
