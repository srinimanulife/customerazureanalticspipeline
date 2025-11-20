variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "customer-analytics"
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "East US"
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Department = "Data Engineering"
    CostCenter = "Analytics"
  }
}

# AAD Groups
variable "aad_group_data_engineers" {
  description = "AAD group name for data engineers"
  type        = string
  default     = "data-engineers"
}

variable "aad_group_data_analysts" {
  description = "AAD group name for data analysts"
  type        = string
  default     = "data-analysts"
}

variable "aad_group_admins" {
  description = "AAD group name for platform admins"
  type        = string
  default     = "data-platform-admins"
}

# Storage
variable "storage_account_tier" {
  description = "Storage account tier"
  type        = string
  default     = "Standard"
}

variable "storage_replication_type" {
  description = "Storage replication type"
  type        = string
  default     = "LRS"
}

# Databricks
variable "databricks_sku" {
  description = "Databricks SKU (standard, premium, trial)"
  type        = string
  default     = "premium"
}

variable "databricks_cluster_version" {
  description = "Databricks runtime version"
  type        = string
  default     = "13.3.x-scala2.12"
}

# Synapse
variable "synapse_sql_admin_username" {
  description = "Synapse SQL admin username"
  type        = string
  default     = "sqladmin"
}

variable "synapse_sql_admin_password" {
  description = "Synapse SQL admin password"
  type        = string
  sensitive   = true
}

# Data Factory
variable "adf_git_integration" {
  description = "Enable Git integration for Data Factory"
  type        = bool
  default     = false
}
