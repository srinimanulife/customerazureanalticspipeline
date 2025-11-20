# Azure Government Cloud - Interview Q&A

## Azure Government Cloud Specific Questions

This document covers questions specific to Azure Government Cloud (Virginia region), which has stricter security, compliance, and connectivity requirements compared to commercial Azure.

---

## Table of Contents
1. [Azure Government Fundamentals](#azure-government-fundamentals)
2. [Compliance and Security](#compliance-and-security)
3. [Networking and Connectivity](#networking-and-connectivity)
4. [Data Residency and Sovereignty](#data-residency-and-sovereignty)
5. [Azure Services in Gov Cloud](#azure-services-in-gov-cloud)
6. [Terraform for Azure Government](#terraform-for-azure-government)
7. [Monitoring and Operations](#monitoring-and-operations)
8. [Common Challenges](#common-challenges)

---

## Azure Government Fundamentals

### Q1: What is Azure Government and why is it different from commercial Azure?

**Answer:**
"Azure Government is a separate, physically isolated cloud instance designed specifically for US federal, state, local, and tribal governments and their partners.

**Key Differences:**

**1. Physical Isolation:**
- Completely separate datacenters from commercial Azure
- Virginia, Texas, Arizona regions (DoD Central, DoD East)
- No network connectivity to commercial Azure
- Physically isolated at network, storage, and compute layers

**2. Personnel Requirements:**
- Only screened US persons (citizens/permanent residents) can access
- Government agencies can request US citizen-only support
- Background checks required for Microsoft personnel

**3. Compliance Frameworks:**
- FedRAMP High authorization
- DoD Impact Level 2, 4, 5 (depending on region)
- CJIS (Criminal Justice Information Services)
- IRS 1075
- NIST 800-53
- DFARS (Defense Federal Acquisition Regulation Supplement)
- ITAR (International Traffic in Arms Regulations)

**4. Different Endpoints:**
```bash
# Commercial Azure
https://portal.azure.com
https://management.azure.com

# Azure Government
https://portal.azure.us
https://management.usgovcloudapi.net
```

**5. Service Availability:**
- Not all Azure services available
- Some services lag behind commercial cloud in features
- Must verify service availability in Gov cloud

**Why Choose Azure Government:**
- Required for government agencies
- Handling controlled unclassified information (CUI)
- Defense contracts requiring DoD compliance
- Law enforcement data (CJIS)
- Healthcare data requiring FedRAMP
- Tax information (IRS 1075)"

---

### Q2: Which Virginia datacenter are you using and what compliance levels does it support?

**Answer:**
"I'm using **US Gov Virginia** which is the primary Azure Government region.

**Location Details:**
- Physical location: Virginia (East Coast)
- Azure Region Name: `usgovvirginia`
- Paired Region: `usgovtexas` (for disaster recovery)
- Also known as: US Gov East

**Compliance Levels:**

**1. FedRAMP High:**
- Authorized at the High impact level
- Suitable for most federal agency workloads
- Covers moderate and high impact data

**2. DoD Impact Level:**
- Supports IL2 and IL4 workloads
- IL5 available in dedicated DoD regions (DoD Central, DoD East)
- IL2: Unclassified information approved for public release
- IL4: Controlled Unclassified Information (CUI)

**3. Other Compliance:**
- CJIS (Criminal Justice Information Services)
- HIPAA/HITECH (Healthcare data)
- IRS 1075 (Tax information)
- NIST 800-53 controls
- Section 508 accessibility

**Terraform Configuration:**
```hcl
provider "azurerm" {
  features {}

  # Azure Government Cloud
  environment = "usgovernment"

  # Endpoints are automatically set for Gov cloud
  # management: https://management.usgovcloudapi.net
  # active_directory: https://login.microsoftonline.us
}

variable "location" {
  description = "Azure Government region"
  type        = string
  default     = "usgovvirginia"  # Not "eastus"

  validation {
    condition = contains([
      "usgovvirginia",
      "usgovtexas",
      "usgovarizona"
    ], var.location)
    error_message = "Location must be a valid Azure Government region"
  }
}
```

**Impact on Architecture:**
- Use paired region for geo-redundancy
- Some services not available in Virginia (check roadmap)
- Network latency considerations for cross-region
- Data residency stays within US sovereign boundaries"

---

## Compliance and Security

### Q3: How do you ensure FedRAMP High compliance in your data platform?

**Answer:**
"FedRAMP High compliance requires implementing strict security controls:

**1. Boundary Protection (SC-7):**
```hcl
# Network isolation
resource "azurerm_virtual_network" "main" {
  name                = "customer-analytics-vnet"
  location            = "usgovvirginia"
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.0.0.0/16"]

  tags = {
    Compliance = "FedRAMP-High"
  }
}

# Private endpoints for all PaaS services
resource "azurerm_private_endpoint" "databricks" {
  name                = "databricks-private-endpoint"
  location            = "usgovvirginia"
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "databricks-connection"
    private_connection_resource_id = azurerm_databricks_workspace.main.id
    subresource_names              = ["databricks_ui_api"]
  }
}

# Disable public access
resource "azurerm_storage_account" "main" {
  public_network_access_enabled = false  # No internet access
}
```

**2. Audit and Accountability (AU Family):**
```hcl
# All resources send logs to dedicated Log Analytics
resource "azurerm_log_analytics_workspace" "compliance" {
  name                = "fedramp-compliance-logs"
  location            = "usgovvirginia"
  resource_group_name = azurerm_resource_group.main.name
  retention_in_days   = 365  # Retain for 1 year minimum

  tags = {
    Compliance = "FedRAMP-High"
    DataType   = "Audit-Logs"
  }
}

# Diagnostic settings for ALL resources
resource "azurerm_monitor_diagnostic_setting" "storage_audit" {
  name                       = "storage-audit-logs"
  target_resource_id         = azurerm_storage_account.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.compliance.id

  # All log categories enabled
  enabled_log {
    category = "StorageRead"
  }
  enabled_log {
    category = "StorageWrite"
  }
  enabled_log {
    category = "StorageDelete"
  }

  metric {
    category = "AllMetrics"
  }
}
```

**3. Identification and Authentication (IA Family):**
```hcl
# Multi-factor authentication enforced via Azure AD Conditional Access
# (Configured at tenant level)

# No SQL authentication allowed
resource "azurerm_synapse_workspace" "main" {
  sql_administrator_login          = null  # Disable SQL auth
  sql_administrator_login_password = null

  # Azure AD admin only
  aad_admin {
    login     = azuread_group.admins.display_name
    object_id = azuread_group.admins.object_id
    tenant_id = data.azurerm_client_config.current.tenant_id
  }

  # Managed identity for service-to-service
  identity {
    type = "SystemAssigned"
  }
}
```

**4. System and Communications Protection (SC Family):**
```hcl
# TLS 1.2 minimum everywhere
resource "azurerm_storage_account" "main" {
  enable_https_traffic_only = true
  min_tls_version          = "TLS1_2"
}

# Encryption at rest with customer-managed keys
resource "azurerm_storage_account_customer_managed_key" "main" {
  storage_account_id = azurerm_storage_account.main.id
  key_vault_id       = azurerm_key_vault.main.id
  key_name           = azurerm_key_vault_key.storage.name
}

# Key Vault with HSM protection
resource "azurerm_key_vault" "main" {
  sku_name                   = "premium"  # HSM-backed
  purge_protection_enabled   = true       # Cannot be deleted
  soft_delete_retention_days = 90

  network_acls {
    default_action = "Deny"  # No public access
    bypass         = "None"
    ip_rules       = []
    virtual_network_subnet_ids = [
      azurerm_subnet.private_endpoints.id
    ]
  }
}
```

**5. Configuration Management (CM Family):**
```hcl
# All infrastructure in version-controlled Terraform
# Resource locks on production resources
resource "azurerm_management_lock" "storage" {
  name       = "prevent-deletion"
  scope      = azurerm_storage_account.main.id
  lock_level = "CanNotDelete"
  notes      = "FedRAMP compliance: Prevent accidental deletion"
}

# Tags for all resources
locals {
  compliance_tags = {
    Compliance     = "FedRAMP-High"
    DataClassification = "CUI"  # Controlled Unclassified Information
    ImpactLevel    = "IL4"
    SystemOwner    = "Data Platform Team"
    FISMA_ID       = "12345"  # FISMA system identifier
    ATO_Date       = "2025-01-01"  # Authority to Operate date
  }
}
```

**6. Incident Response (IR Family):**
```hcl
# Real-time security alerts
resource "azurerm_security_center_subscription_pricing" "main" {
  tier          = "Standard"  # Defender for Cloud
  resource_type = "VirtualMachines"
}

# Alert on security events
resource "azurerm_monitor_metric_alert" "unauthorized_access" {
  name = "unauthorized-access-attempt"

  criteria {
    metric_name = "UnauthorizedAccess"
    aggregation = "Total"
    operator    = "GreaterThan"
    threshold   = 0
  }

  action {
    # Send to Security Operations Center
    action_group_id = azurerm_monitor_action_group.soc.id
  }
}
```

**7. Media Protection (MP Family):**
```python
# Data sanitization in Databricks
def sanitize_data(df):
    """Remove PII before processing"""
    return df \
        .withColumn("ssn", lit(None)) \
        .withColumn("email", sha2(col("email"), 256))  # Hash PII

# Ensure data doesn't leave authorized boundaries
spark.conf.set("spark.sql.execution.arrow.enabled", "false")  # No Arrow export
```

**Documentation Required:**
- System Security Plan (SSP)
- Continuous monitoring plan
- Incident response plan
- Disaster recovery plan
- Data flow diagrams
- Control implementation statements"

---

### Q4: How do you handle data classification and CUI (Controlled Unclassified Information)?

**Answer:**
"CUI requires specific handling procedures:

**1. Data Classification:**
```hcl
# Tag all resources with classification
resource "azurerm_storage_account" "main" {
  name = "customersacui"

  tags = {
    DataClassification = "CUI"
    CUICategory        = "Law Enforcement"  # Or Tax, Health, etc.
    HandlingCaveat     = "CUI//SP-LAW"     # Special handling
    Dissemination      = "FEDONLY"          # Federal only
    AuthorizedUsers    = "AAD-Group-DataEngineers"
  }
}

# Container-level classification
resource "azurerm_storage_container" "bronze" {
  name     = "bronze"
  metadata = {
    classification = "CUI"
    category      = "unprocessed-data"
    retention     = "7-years"
  }
}
```

**2. Access Control for CUI:**
```hcl
# Separate AAD groups for CUI access
resource "azuread_group" "cui_authorized" {
  display_name     = "CUI-Authorized-Personnel"
  security_enabled = true
  description      = "Personnel authorized to access CUI data"

  # Membership managed by security team
  # Requires background checks and training
}

# Role assignment only for authorized personnel
resource "azurerm_role_assignment" "cui_access" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azuread_group.cui_authorized.object_id

  condition = <<-EOT
    (
      @Request[Microsoft.Storage/storageAccounts/blobServices/containers:name]
      StringEquals 'cui-approved-container'
    )
  EOT
}
```

**3. Data Loss Prevention:**
```hcl
# Private endpoints only - no internet access
resource "azurerm_storage_account" "main" {
  public_network_access_enabled = false

  network_rules {
    default_action = "Deny"
    bypass         = "None"  # No bypasses

    # Only specific VNets can access
    virtual_network_subnet_ids = [
      azurerm_subnet.databricks.id,
      azurerm_subnet.synapse.id
    ]
  }
}

# Disable file sharing features
resource "azurerm_storage_account" "main" {
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false  # No SAS tokens
  allow_blob_public_access        = false
}
```

**4. Databricks CUI Handling:**
```python
# Databricks notebook for CUI
# Add warning banner
dbutils.widgets.text("CLASSIFICATION", "CUI//SP-LAW", "Data Classification")

# Validate user authorization
current_user = dbutils.notebook.entry_point.getDbutils().\
    notebook().getContext().userName().get()

authorized_users = ["user1@agency.gov", "user2@agency.gov"]
if current_user not in authorized_users:
    raise PermissionError(f"User {current_user} not authorized for CUI data")

# Audit all data access
audit_log = {
    "user": current_user,
    "action": "data_access",
    "classification": "CUI",
    "timestamp": datetime.now(),
    "data_path": bronze_path
}
log_to_compliance_system(audit_log)

# Prevent data exfiltration
spark.conf.set("spark.databricks.repl.allowedLanguages", "python,sql")  # No Scala
dbutils.notebook.exit("Processing complete - data remains in secure environment")
```

**5. Data at Rest Encryption:**
```hcl
# Customer-managed keys with FIPS 140-2 Level 2 HSM
resource "azurerm_key_vault" "main" {
  sku_name = "premium"  # HSM-backed

  tags = {
    CryptoModule = "FIPS-140-2-Level-2"
  }
}

resource "azurerm_key_vault_key" "storage" {
  name         = "storage-cmk"
  key_vault_id = azurerm_key_vault.main.id
  key_type     = "RSA-HSM"  # Hardware Security Module
  key_size     = 4096       # Strong encryption

  key_opts = [
    "decrypt",
    "encrypt",
    "unwrapKey",
    "wrapKey",
  ]
}

# Apply to all storage
resource "azurerm_storage_account_customer_managed_key" "main" {
  storage_account_id = azurerm_storage_account.main.id
  key_vault_id       = azurerm_key_vault.main.id
  key_name           = azurerm_key_vault_key.storage.name
}
```

**6. CUI Marking and Labeling:**
```python
# Add CUI banner to all data frames
def add_cui_marking(df):
    return df.withColumn(
        "_classification",
        lit("CUI//SP-LAW//FED ONLY")
    ).withColumn(
        "_handling_instructions",
        lit("Authorized Use Only - See NIST SP 800-171")
    )

# Apply to all datasets
silver_df = add_cui_marking(bronze_df.transform(clean_data))
```

**7. CUI Audit Requirements:**
```kusto
// Track all CUI data access
StorageBlobLogs
| where AccountName == "customersacui"
| where Category == "StorageRead" or Category == "StorageWrite"
| extend Classification = "CUI"
| project
    TimeGenerated,
    CallerIdentity,
    ObjectKey,
    OperationName,
    Classification,
    StatusCode
| where CallerIdentity !contains "System"  // Only user access
```

**8. Training Requirements:**
- All users must complete CUI training
- Annual refresher training
- Documented in personnel files
- Track in AAD group membership requirements

**9. Incident Reporting:**
```
CUI incidents must be reported:
- Within 1 hour: Security team
- Within 24 hours: Agency CISO
- Within 72 hours: US-CERT (if applicable)
```"

---

## Networking and Connectivity

### Q5: How do you handle networking in Azure Government with stricter connectivity requirements?

**Answer:**
"Azure Government networking is more restrictive and requires careful planning:

**1. VNet Architecture:**
```hcl
# Hub-and-spoke topology (common in Gov)
resource "azurerm_virtual_network" "hub" {
  name                = "hub-vnet"
  location            = "usgovvirginia"
  resource_group_name = azurerm_resource_group.network.name
  address_space       = ["10.0.0.0/16"]

  tags = {
    Environment = "Production"
    Compliance  = "FedRAMP-High"
  }
}

resource "azurerm_virtual_network" "spoke_data" {
  name                = "spoke-data-platform-vnet"
  location            = "usgovvirginia"
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.1.0.0/16"]
}

# VNet peering
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                      = "hub-to-data-platform"
  resource_group_name       = azurerm_resource_group.network.name
  virtual_network_name      = azurerm_virtual_network.hub.name
  remote_virtual_network_id = azurerm_virtual_network.spoke_data.id
  allow_forwarded_traffic   = true
  allow_gateway_transit     = true
}
```

**2. Subnetting Strategy:**
```hcl
# Separate subnets for each service
resource "azurerm_subnet" "databricks_public" {
  name                 = "databricks-public-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.spoke_data.name
  address_prefixes     = ["10.1.1.0/24"]

  delegation {
    name = "databricks"
    service_delegation {
      name = "Microsoft.Databricks/workspaces"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
        "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action",
      ]
    }
  }
}

resource "azurerm_subnet" "databricks_private" {
  name                 = "databricks-private-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.spoke_data.name
  address_prefixes     = ["10.1.2.0/24"]

  delegation {
    name = "databricks"
    service_delegation {
      name = "Microsoft.Databricks/workspaces"
    }
  }
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "private-endpoints-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.spoke_data.name
  address_prefixes     = ["10.1.3.0/24"]

  private_endpoint_network_policies_enabled = false
}
```

**3. Private Endpoints (Required for Gov Cloud):**
```hcl
# Storage private endpoint
resource "azurerm_private_endpoint" "storage" {
  name                = "storage-private-endpoint"
  location            = "usgovvirginia"
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "storage-connection"
    private_connection_resource_id = azurerm_storage_account.main.id
    subresource_names              = ["blob"]  # Also: dfs, file, table
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "blob-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
}

# Private DNS Zone for name resolution
resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.usgovcloudapi.net"  # Gov cloud endpoint
  resource_group_name = azurerm_resource_group.network.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = "blob-dns-link"
  resource_group_name   = azurerm_resource_group.network.name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = azurerm_virtual_network.spoke_data.id
}
```

**4. Network Security Groups:**
```hcl
resource "azurerm_network_security_group" "databricks" {
  name                = "databricks-nsg"
  location            = "usgovvirginia"
  resource_group_name = azurerm_resource_group.main.name

  # Deny all inbound by default
  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow only necessary outbound (Azure services)
  security_rule {
    name                       = "AllowAzureServicesOutbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureCloud.usgovvirginia"
  }

  # Explicit deny internet
  security_rule {
    name                       = "DenyInternetOutbound"
    priority                   = 4000
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }
}
```

**5. Azure Firewall (Hub):**
```hcl
# Centralized egress control
resource "azurerm_firewall" "hub" {
  name                = "hub-firewall"
  location            = "usgovvirginia"
  resource_group_name = azurerm_resource_group.network.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Premium"  # Required for TLS inspection

  ip_configuration {
    name                 = "firewall-config"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }
}

# Application rules - whitelist approach
resource "azurerm_firewall_application_rule_collection" "databricks" {
  name                = "databricks-rules"
  azure_firewall_name = azurerm_firewall.hub.name
  resource_group_name = azurerm_resource_group.network.name
  priority            = 100
  action              = "Allow"

  rule {
    name = "databricks-control-plane"
    source_addresses = ["10.1.0.0/16"]  # Spoke VNet

    target_fqdns = [
      "*.databricks.azure.us",  # Gov cloud endpoint
      "*.blob.core.usgovcloudapi.net",
      "*.azuresynapse.usgovcloudapi.net"
    ]

    protocol {
      port = "443"
      type = "Https"
    }
  }
}

# Network rules for specific IPs
resource "azurerm_firewall_network_rule_collection" "azure_services" {
  name                = "azure-services"
  azure_firewall_name = azurerm_firewall.hub.name
  resource_group_name = azurerm_resource_group.network.name
  priority            = 200
  action              = "Allow"

  rule {
    name                  = "azure-services-https"
    source_addresses      = ["10.0.0.0/8"]
    destination_addresses = ["AzureCloud.usgovvirginia"]
    destination_ports     = ["443"]
    protocols             = ["TCP"]
  }
}
```

**6. ExpressRoute (Recommended for Gov):**
```hcl
# Dedicated connection to on-premises government network
resource "azurerm_express_route_circuit" "main" {
  name                  = "gov-agency-expressroute"
  resource_group_name   = azurerm_resource_group.network.name
  location              = "usgovvirginia"
  service_provider_name = "Level 3"  # Or other approved provider
  peering_location      = "Washington DC"
  bandwidth_in_mbps     = 1000

  sku {
    tier   = "Premium"  # Required for Gov cloud
    family = "MeteredData"
  }

  tags = {
    Compliance = "FedRAMP-High"
  }
}

# Gateway connection
resource "azurerm_virtual_network_gateway" "hub" {
  name                = "hub-vnet-gateway"
  location            = "usgovvirginia"
  resource_group_name = azurerm_resource_group.network.name

  type     = "ExpressRoute"
  sku      = "ErGw3AZ"  # Zone-redundant

  ip_configuration {
    name                          = "gateway-config"
    public_ip_address_id          = azurerm_public_ip.gateway.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway.id
  }
}
```

**7. Bastion for Secure Access:**
```hcl
# Azure Bastion for RDP/SSH without public IPs
resource "azurerm_bastion_host" "main" {
  name                = "secure-bastion"
  location            = "usgovvirginia"
  resource_group_name = azurerm_resource_group.network.name
  sku                 = "Standard"

  ip_configuration {
    name                 = "bastion-config"
    subnet_id            = azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }

  # Premium features
  tunneling_enabled = true
  file_copy_enabled = true
}
```

**8. Service Endpoints vs Private Endpoints:**
```
Azure Government Recommendation: Use Private Endpoints

Why:
- Service endpoints still use public IPs (even if traffic doesn't leave Microsoft backbone)
- Private endpoints provide private IPs (10.x.x.x)
- Required for IL4/IL5 workloads
- Better for compliance audits
```

**Key Differences from Commercial:**
- Must use `.usgovcloudapi.net` endpoints
- Private endpoints use different DNS zones
- Some regions not available
- ExpressRoute strongly recommended over VPN
- More stringent NSG rules
- No direct internet connectivity typically allowed"

---

### Q6: How do you connect on-premises government networks to Azure Government?

**Answer:**
"Government agencies typically have strict network security requirements:

**1. ExpressRoute (Recommended):**
```
Why ExpressRoute for Gov:
- Dedicated fiber connection
- Does not traverse public internet
- Required for classified/CUI data
- Predictable latency and bandwidth
- Can use for both Azure and Microsoft 365 Gov
- Supports up to 100 Gbps
```

**Architecture:**
```
On-Premises Gov Network
          ↓
    [MPLS/Carrier]
          ↓
  ExpressRoute Circuit
          ↓
ExpressRoute Gateway (Hub VNet)
          ↓
    VNet Peering
          ↓
Data Platform Spoke VNet
```

**Terraform:**
```hcl
# ExpressRoute Connection
resource "azurerm_virtual_network_gateway_connection" "expressroute" {
  name                = "onprem-to-azure-gov"
  location            = "usgovvirginia"
  resource_group_name = azurerm_resource_group.network.name

  type                       = "ExpressRoute"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.hub.id
  express_route_circuit_id   = azurerm_express_route_circuit.main.id

  # Encryption over ExpressRoute
  express_route_gateway_bypass = false

  tags = {
    Connection = "OnPremises-to-AzureGov"
    Compliance = "FISMA-Approved"
  }
}
```

**2. Site-to-Site VPN (Alternative):**
```hcl
# For smaller agencies or secondary connection
resource "azurerm_virtual_network_gateway" "vpn" {
  name                = "vpn-gateway"
  location            = "usgovvirginia"
  resource_group_name = azurerm_resource_group.network.name

  type     = "Vpn"
  vpn_type = "RouteBased"
  sku      = "VpnGw2AZ"  # Zone-redundant

  active_active = true  # Redundancy

  ip_configuration {
    name                 = "primary"
    public_ip_address_id = azurerm_public_ip.vpn_primary.id
    subnet_id            = azurerm_subnet.gateway.id
  }

  ip_configuration {
    name                 = "secondary"
    public_ip_address_id = azurerm_public_ip.vpn_secondary.id
    subnet_id            = azurerm_subnet.gateway.id
  }

  vpn_client_configuration {
    address_space = ["172.16.0.0/24"]

    # Point-to-site for remote users
    vpn_client_protocols = ["IkeV2"]  # Most secure

    # Certificate-based auth (not username/password)
    root_certificate {
      name             = "gov-agency-root-cert"
      public_cert_data = file("${path.module}/certs/root-cert.cer")
    }
  }
}

# Local network gateway (on-premises side)
resource "azurerm_local_network_gateway" "onprem" {
  name                = "onprem-gateway"
  location            = "usgovvirginia"
  resource_group_name = azurerm_resource_group.network.name

  gateway_address = "203.0.113.10"  # On-prem public IP

  address_space = [
    "192.168.0.0/16"  # On-prem network
  ]

  bgp_settings {
    asn                 = 65001
    bgp_peering_address = "192.168.1.1"
  }
}

# VPN Connection
resource "azurerm_virtual_network_gateway_connection" "s2s" {
  name                = "onprem-vpn"
  location            = "usgovvirginia"
  resource_group_name = azurerm_resource_group.network.name

  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.vpn.id
  local_network_gateway_id   = azurerm_local_network_gateway.onprem.id

  shared_key = azurerm_key_vault_secret.vpn_psk.value  # From Key Vault

  # IPsec/IKE policy for NIST compliance
  ipsec_policy {
    dh_group         = "ECP384"      # Elliptic Curve Diffie-Hellman
    ike_encryption   = "GCMAES256"   # Galois/Counter Mode AES
    ike_integrity    = "SHA384"      # SHA-384 for integrity
    ipsec_encryption = "GCMAES256"
    ipsec_integrity  = "GCMAES256"
    pfs_group        = "ECP384"      # Perfect Forward Secrecy
    sa_lifetime      = 27000         # Security Association lifetime
  }

  use_policy_based_traffic_selectors = false
  enable_bgp                        = true
}
```

**3. User Access - Azure AD Gov:**
```hcl
# Azure AD Government tenant (separate from commercial)
# portal.azure.us login

# Conditional Access Policies
# (Configured in Azure AD Gov portal)
/*
Policy: Government Agency Access

Conditions:
- User location: Must be on-premises or Azure VNet
- Device compliance: Required
- MFA: Required
- Approved client apps only

Actions:
- Block: Consumer accounts (outlook.com, gmail.com)
- Block: Non-US IP addresses
- Require: Government-issued device
*/
```

**4. DNS Resolution:**
```hcl
# Custom DNS servers for hybrid resolution
resource "azurerm_virtual_network" "spoke_data" {
  name          = "spoke-data-vnet"
  address_space = ["10.1.0.0/16"]

  dns_servers = [
    "192.168.1.10",  # On-premises DNS (primary)
    "192.168.1.11",  # On-premises DNS (secondary)
    "168.63.129.16"  # Azure recursive DNS (fallback)
  ]
}

# Private DNS forwarding
# On-prem DNS servers forward *.azure.us queries to Azure DNS
# Azure DNS forwards internal agency queries to on-prem DNS
```

**5. Routing:**
```hcl
# User-defined routes for hybrid connectivity
resource "azurerm_route_table" "hybrid" {
  name                = "hybrid-routes"
  location            = "usgovvirginia"
  resource_group_name = azurerm_resource_group.network.name

  route {
    name                   = "to-onprem"
    address_prefix         = "192.168.0.0/16"
    next_hop_type          = "VirtualNetworkGateway"
    next_hop_in_ip_address = null
  }

  route {
    name           = "to-azure-services"
    address_prefix = "AzureCloud.usgovvirginia"
    next_hop_type  = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_firewall.hub.ip_configuration[0].private_ip_address
  }

  # Force tunnel all internet through on-premises (common for Gov)
  route {
    name                   = "force-tunnel-internet"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualNetworkGateway"
  }
}
```

**6. Network Monitoring:**
```hcl
# Network Watcher for traffic analysis
resource "azurerm_network_watcher" "main" {
  name                = "network-watcher-gov"
  location            = "usgovvirginia"
  resource_group_name = azurerm_resource_group.network.name
}

# Flow logs for compliance
resource "azurerm_network_watcher_flow_log" "nsg" {
  network_watcher_name = azurerm_network_watcher.main.name
  resource_group_name  = azurerm_resource_group.network.name
  name                 = "nsg-flow-logs"

  network_security_group_id = azurerm_network_security_group.databricks.id
  storage_account_id        = azurerm_storage_account.logs.id
  enabled                   = true
  version                   = 2
  retention_policy {
    enabled = true
    days    = 365  # Keep for compliance
  }

  traffic_analytics {
    enabled               = true
    workspace_id          = azurerm_log_analytics_workspace.compliance.workspace_id
    workspace_region      = "usgovvirginia"
    workspace_resource_id = azurerm_log_analytics_workspace.compliance.id
    interval_in_minutes   = 10
  }
}
```

**7. Bandwidth Considerations:**
```
ExpressRoute Sizing:
- Dev/Test: 100 Mbps
- Production (< 100 users): 1 Gbps
- Production (100-500 users): 2-5 Gbps
- Large agency: 10 Gbps+

Factors:
- Data volume to/from Azure
- Number of concurrent users
- Replication traffic
- Backup traffic
```"

---

## Azure Services in Gov Cloud

### Q7: Which Azure services are available in Azure Government and which have limitations?

**Answer:**
"Not all Azure services are available in Government cloud:

**Fully Available Services (in US Gov Virginia):**
```
✅ Core Services:
- Virtual Machines
- Virtual Networks
- Storage Accounts (Blob, File, Queue, Table)
- Azure SQL Database
- Azure Key Vault
- Azure Active Directory
- Load Balancers
- Application Gateway
- Azure Firewall

✅ Data & Analytics:
- Azure Synapse Analytics (formerly SQL Data Warehouse)
- Azure Databricks ✅ (Since 2020)
- Azure Data Factory ✅
- HDInsight
- Azure Data Lake Storage Gen2

✅ Security & Management:
- Microsoft Defender for Cloud
- Azure Monitor
- Log Analytics
- Azure Policy
- Azure Blueprints
- Azure Private Link

✅ DevOps:
- Azure DevOps Services (separate instance: dev.azure.us)
- GitHub (commercial, with compliance considerations)
```

**Limited Availability:**
```
⚠️ Available with Limitations:
- Azure Machine Learning (Limited regions)
- Cognitive Services (Subset available)
- Azure Functions (Available but later feature releases)
- Power BI Government (Separate service)
```

**Not Available or Restricted:**
```
❌ Not in Gov Cloud:
- Azure OpenAI (Not available - requires separate approval process)
- Some Cognitive Services
- Azure Digital Twins
- Some preview features lag behind commercial
- Certain IoT services

⏳ Coming Soon:
- Check Azure Government roadmap
- https://azure.microsoft.com/en-us/global-infrastructure/services/?products=all&regions=non-regional,usgov-non-regional,us-dod-central,us-dod-east,usgov-arizona,usgov-texas,usgov-virginia
```

**Impact on Our Architecture:**

**1. Databricks:**
```hcl
# Verify Databricks is available in region
resource "azurerm_databricks_workspace" "main" {
  name                = "customer-analytics-dbw"
  location            = "usgovvirginia"  # Supported
  # location          = "usgovtexas"     # Also supported
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "premium"

  # Gov cloud specific settings
  public_network_access_enabled = false  # Required for compliance

  custom_parameters {
    no_public_ip                                         = true
    virtual_network_id                                   = azurerm_virtual_network.spoke_data.id
    public_subnet_name                                   = azurerm_subnet.databricks_public.name
    private_subnet_name                                  = azurerm_subnet.databricks_private.name
    public_subnet_network_security_group_association_id  = azurerm_subnet_network_security_group_association.databricks_public.id
    private_subnet_network_security_group_association_id = azurerm_subnet_network_security_group_association.databricks_private.id
  }
}

# Databricks provider for Gov cloud
provider "databricks" {
  host                        = "https://${azurerm_databricks_workspace.main.workspace_url}"
  azure_workspace_resource_id = azurerm_databricks_workspace.main.id

  # Azure Government authentication
  azure_environment = "usgovernment"
}
```

**2. Data Factory:**
```hcl
# Fully supported in Gov Virginia
resource "azurerm_data_factory" "main" {
  name                = "customer-analytics-adf"
  location            = "usgovvirginia"
  resource_group_name = azurerm_resource_group.main.name

  # Gov cloud endpoints automatically used
  identity {
    type = "SystemAssigned"
  }

  # Note: Some connectors may not be available
  # Check: https://docs.microsoft.com/en-us/azure/data-factory/connector-overview
  # Most common connectors (Blob, ADLS, SQL) are supported
}

# Git integration works but must use Azure DevOps Gov or on-premises Git
resource "azurerm_data_factory_integration_runtime_azure" "main" {
  name            = "AutoResolveIntegrationRuntime"
  data_factory_id = azurerm_data_factory.main.id
  location        = "usgovvirginia"

  # Ensure region matches
  compute_type = "General"
  core_count   = 8
  time_to_live_min = 10
}
```

**3. Synapse:**
```hcl
# Synapse Analytics available in US Gov Virginia
resource "azurerm_synapse_workspace" "main" {
  name                = "customersynapsegov"
  location            = "usgovvirginia"
  resource_group_name = azurerm_resource_group.main.name

  # Gov cloud storage endpoint
  storage_data_lake_gen2_filesystem_id = azurerm_storage_data_lake_gen2_filesystem.synapse.id

  # AAD admin in Gov tenant
  aad_admin {
    login     = azuread_group.admins.display_name
    object_id = azuread_group.admins.object_id
    tenant_id = data.azurerm_client_config.current.tenant_id
  }

  # Note: Some Synapse features may lag behind commercial
  # - Link to Power BI: Use Power BI Government
  # - Synapse Link: Check availability
  # - Synapse Studio: Separate URL (.usgovcloudapi.net)
}
```

**4. Alternative Solutions:**
```
If a service isn't available:

Azure OpenAI → Use on-premises models or approved alternatives
Consumer AI Services → Wait for Gov cloud release
Preview Features → Wait for GA in Gov cloud
```

**5. Service Verification Before Deployment:**
```bash
# Check service availability
az cloud set --name AzureUSGovernment

az account list-locations --query "[?name=='usgovvirginia'].{Name:name, DisplayName:displayName}"

# List available services
az provider list --query "[?registrationState=='Registered'].namespace" -o table
```

**6. Version Lag:**
```
Common Pattern:
- Feature released in Commercial Azure: Month 0
- FedRAMP review: Months 1-3
- Available in Gov Cloud: Months 3-6
- DoD regions: Months 6-12

Example:
- Databricks Unity Catalog: Commercial (2022), Gov (2023)
- Synapse Serverless: Commercial (2020), Gov (2021)
```

**7. Documentation:**
```
Always check:
- Azure Gov Documentation: https://docs.microsoft.com/en-us/azure/azure-government/
- Service availability: https://azure.microsoft.com/en-us/global-infrastructure/services/?regions=usgov-non-regional,us-dod-central,us-dod-east,usgov-arizona,usgov-texas,usgov-virginia
- Azure Gov Roadmap: https://azure.microsoft.com/en-us/updates/?category=azure-government
```"

---

## Terraform for Azure Government

### Q8: What are the Terraform-specific considerations for Azure Government?

**Answer:**
"Terraform for Azure Government requires specific configuration:

**1. Provider Configuration:**
```hcl
terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
  }

  # Backend must also use Gov cloud
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "tfstategov123"
    container_name       = "tfstate"
    key                  = "terraform.tfstate"

    # CRITICAL: Set environment for Gov cloud
    environment = "usgovernment"

    # Gov cloud endpoints
    # Automatically uses:
    # - https://management.usgovcloudapi.net
    # - https://login.microsoftonline.us
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy    = false  # Keep for compliance
      recover_soft_deleted_key_vaults = true
    }
  }

  # CRITICAL: Azure Government Cloud
  environment = "usgovernment"

  # Endpoints are automatically set:
  # - Resource Manager: management.usgovcloudapi.net
  # - Active Directory: login.microsoftonline.us
  # - Storage: core.usgovcloudapi.net

  # Subscription must be in Azure Gov tenant
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

provider "azuread" {
  # AAD provider also needs Gov cloud
  environment = "usgovernment"

  tenant_id = var.tenant_id
}
```

**2. Region Names:**
```hcl
# Valid Gov cloud regions (different from commercial)
variable "location" {
  description = "Azure Government region"
  type        = string
  default     = "usgovvirginia"

  validation {
    condition = contains([
      "usgovvirginia",   # US Gov Virginia
      "usgovtexas",      # US Gov Texas
      "usgovarizona",    # US Gov Arizona
      "usdodeast",       # US DoD East
      "usdodcentral"     # US DoD Central
    ], var.location)
    error_message = "Must be a valid Azure Government region"
  }
}

# INCORRECT - these don't exist in Gov cloud:
# - "eastus"
# - "westus"
# - "centralus"
```

**3. Storage Endpoints:**
```hcl
resource "azurerm_storage_account" "main" {
  name = "customersagov"

  # Endpoints are different in Gov cloud
  # Commercial: blob.core.windows.net
  # Government: blob.core.usgovcloudapi.net

  # Terraform handles this automatically when environment = "usgovernment"
}

# When constructing URLs manually:
locals {
  # DON'T hardcode commercial endpoints
  # storage_url = "https://${azurerm_storage_account.main.name}.blob.core.windows.net"  # ❌ WRONG

  # Use Terraform's computed values
  storage_url = azurerm_storage_account.main.primary_blob_endpoint  # ✅ CORRECT
  # Automatically: https://customersagov.blob.core.usgovcloudapi.net
}
```

**4. DNS Zones for Private Endpoints:**
```hcl
# Private DNS zones use Gov cloud domain
resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.usgovcloudapi.net"  # Gov cloud
  resource_group_name = azurerm_resource_group.network.name

  # NOT: "privatelink.blob.core.windows.net" (that's commercial)
}

resource "azurerm_private_dns_zone" "databricks" {
  name                = "privatelink.azuredatabricks.net"  # Same for Gov
  resource_group_name = azurerm_resource_group.network.name
}

resource "azurerm_private_dns_zone" "synapse" {
  name                = "privatelink.sql.azuresynapse.usgovcloudapi.net"  # Gov
  resource_group_name = azurerm_resource_group.network.name
}

# Complete list for Gov cloud:
# - privatelink.blob.core.usgovcloudapi.net
# - privatelink.table.core.usgovcloudapi.net
# - privatelink.queue.core.usgovcloudapi.net
# - privatelink.file.core.usgovcloudapi.net
# - privatelink.web.core.usgovcloudapi.net
# - privatelink.dfs.core.usgovcloudapi.net (ADLS Gen2)
# - privatelink.database.usgovcloudapi.net (SQL)
# - privatelink.azuresynapse.usgovcloudapi.net (Synapse)
# - privatelink.sql.azuresynapse.usgovcloudapi.net (Synapse SQL)
# - privatelink.dev.azuresynapse.usgovcloudapi.net (Synapse Dev)
# - privatelink.vaultcore.usgovcloudapi.net (Key Vault)
```

**5. Authentication:**
```bash
# Azure CLI for Gov cloud
az cloud set --name AzureUSGovernment

az login

# Verify
az account show

# Terraform picks up credentials from Azure CLI
terraform init
terraform plan
```

**6. Service Principal for CI/CD:**
```bash
# Create SP in Gov cloud
az ad sp create-for-rbac \
  --name "terraform-cicd" \
  --role Contributor \
  --scopes /subscriptions/<gov-subscription-id>

# Output:
{
  "appId": "...",
  "displayName": "terraform-cicd",
  "password": "...",
  "tenant": "..."  # Gov tenant ID
}

# Use in GitHub Actions
# ARM_ENDPOINT is set automatically by environment = "usgovernment"
```

**7. Module Considerations:**
```hcl
# If using community modules, verify they support Gov cloud
module "network" {
  source = "Azure/network/azurerm"
  version = "~> 5.0"

  # Pass environment through
  resource_group_name = azurerm_resource_group.main.name
  location            = "usgovvirginia"  # Not "eastus"

  # Some modules may not support Gov cloud - test thoroughly
}

# Better: Write your own modules for full control
module "storage" {
  source = "./modules/storage"

  environment  = "usgovernment"
  location     = var.location
  project_name = var.project_name
}
```

**8. State File Considerations:**
```hcl
# State file contains sensitive data - protect it
terraform {
  backend "azurerm" {
    environment = "usgovernment"

    # Use private endpoint for state storage
    use_microsoft_graph = false
    use_azuread_auth   = true

    # Encryption
    # State file encrypted at rest by default
    # Consider customer-managed key
  }
}

# Alternative: Use Terraform Cloud Government
# https://app.terraform.io (FedRAMP authorized)
```

**9. Databricks Provider:**
```hcl
provider "databricks" {
  host                        = "https://${azurerm_databricks_workspace.main.workspace_url}"
  azure_workspace_resource_id = azurerm_databricks_workspace.main.id

  # CRITICAL: Must specify Gov environment
  azure_environment = "usgovernment"

  # Auth via Azure CLI or service principal
}

# Databricks resources
resource "databricks_cluster" "main" {
  cluster_name  = "gov-cluster"
  spark_version = data.databricks_spark_version.latest.id
  node_type_id  = data.databricks_node_type.smallest.id

  # Everything else same as commercial
}
```

**10. Testing:**
```bash
# Always test in Gov cloud dev environment first
terraform plan -var-file="gov-dev.tfvars"

# Check computed URLs
terraform output storage_primary_endpoint
# Should show: *.usgovcloudapi.net (not *.windows.net)

# Verify resources in Gov portal
# https://portal.azure.us
```

**11. Common Errors:**
```
Error: "The subscription is not registered to use namespace"
Fix: az provider register --namespace Microsoft.Databricks --wait

Error: "The client has permission to perform action Microsoft.Storage/storageAccounts/write but it does not have access to the subscription"
Fix: Wrong tenant - verify you're in Gov tenant

Error: "InvalidResourceNamespace: The resource namespace is invalid"
Fix: Service not available in Gov cloud - check docs
```

**12. Terraform Variables for Gov:**
```hcl
# terraform.tfvars for Gov cloud
environment         = "usgovernment"
location            = "usgovvirginia"
paired_region       = "usgovtexas"
azure_environment   = "usgovernment"

# Endpoints (for manual construction)
storage_endpoint_suffix     = "core.usgovcloudapi.net"
keyvault_endpoint_suffix    = "vault.usgovcloudapi.net"
sql_endpoint_suffix         = "database.usgovcloudapi.net"
resource_manager_endpoint   = "https://management.usgovcloudapi.net"
active_directory_endpoint   = "https://login.microsoftonline.us"
active_directory_graph_resource_id = "https://graph.windows.net/"

# Compliance tags
default_tags = {
  Compliance     = "FedRAMP-High"
  CloudType      = "AzureGovernment"
  DataResidency  = "US-Only"
  ImpactLevel    = "IL4"
}
```"

---

This comprehensive documentation should prepare you well for questions about Azure Government Cloud. The key points to emphasize are:

1. **Physical Isolation**: Completely separate from commercial Azure
2. **Compliance**: FedRAMP High, DoD IL2/IL4/IL5, CJIS
3. **Networking**: Much stricter - private endpoints, ExpressRoute preferred
4. **Different Endpoints**: All `.usgovcloudapi.net` instead of `.windows.net`
5. **Terraform**: Must set `environment = "usgovernment"` in provider
6. **Service Availability**: Not all services available, check roadmap
7. **Security**: Higher bar than commercial - CUI handling, US persons only
8. **Connectivity**: ExpressRoute strongly recommended over internet

Would you like me to add more sections covering specific scenarios or dive deeper into any particular aspect?
