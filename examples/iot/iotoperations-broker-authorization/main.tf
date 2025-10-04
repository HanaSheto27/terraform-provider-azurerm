terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# ---------------- Vars ----------------
variable "resource_group_name" {
  type        = string
  default     = "example-iotoperations"
  description = "Resource Group name to house the IoT Operations instance."
}

variable "location" {
  type        = string
  default     = "West Europe"
  description = "Azure location/region."
}

variable "instance_name" {
  type        = string
  default     = "terraforminstancecreated"
  description = "Name of the IoT Operations instance resource."
}

variable "broker_name" {
  type        = string
  default     = "terraformbroker"
  description = "Name of the IoT Operations broker resource."
}

variable "authorization_name" {
  type        = string
  default     = "terraformauthorization"
  description = "Name of the IoT Operations broker authentication resource."
}

# /subscriptions/<subId>/resourceGroups/<rg>/providers/Microsoft.ExtendedLocation/customLocations/<customLocationName>
variable "custom_location_id" {
  type        = string
  description = "ARM ID of the Custom Location used by AIO."
}

# /subscriptions/<subId>/resourceGroups/<rg>/providers/Microsoft.DeviceRegistry/schemaRegistries/<schemaRegistryName>
variable "schema_registry_id" {
  type        = string
  description = "ARM ID of the Schema Registry referenced by the AIO instance."
}

variable "tags" {
  type = map(string)
  default = {
    Environment = "Dev"
    Owner       = "team"
  }
}

data "azurerm_client_config" "current" {}

# ---------------- RG ----------------
resource "azurerm_resource_group" "example" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# ---------------- AIO Instance (ARM: Microsoft.IoTOperations/instances@2024-11-01) ----------------
resource "azurerm_resource_group_template_deployment" "iotops_instance" {
  name                = "${var.instance_name}-deploy"
  resource_group_name = azurerm_resource_group.example.name
  deployment_mode     = "Incremental"

  template_content = <<JSON
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "instanceName":     { "type": "string" },
    "location":         { "type": "string" },
    "customLocationId": { "type": "string" },
    "schemaRegistryId": { "type": "string" },
    "tags":             { "type": "object" }
  },
  "resources": [
    {
      "type": "Microsoft.IoTOperations/instances",
      "apiVersion": "2024-11-01",
      "name": "[parameters('instanceName')]",
      "location": "[parameters('location')]",
      "extendedLocation": { "type": "CustomLocation", "name": "[parameters('customLocationId')]" },
      "tags": "[parameters('tags')]",
      "properties": {
        "description": "IoT Operations instance (Terraform via AzureRM template)",
        "schemaRegistryRef": { "resourceId": "[parameters('schemaRegistryId')]" }
      }
    }
  ],
  "outputs": {
    "instanceId": { "type": "string", "value": "[resourceId('Microsoft.IoTOperations/instances', parameters('instanceName'))]" }
  }
}
JSON

  parameters_content = jsonencode({
    instanceName     = { value = var.instance_name }
    location         = { value = var.location }
    customLocationId = { value = var.custom_location_id }
    schemaRegistryId = { value = var.schema_registry_id }
    tags             = { value = var.tags }
  })
}

# ---------------- Broker (ARM: Microsoft.IoTOperations/instances/brokers@2024-11-01) ----------------
resource "azurerm_resource_group_template_deployment" "iotops_broker" {
  name                = "${var.broker_name}-deploy"
  resource_group_name = azurerm_resource_group.example.name
  deployment_mode     = "Incremental"

  template_content = <<JSON
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "instanceName":     { "type": "string" },
    "brokerName":       { "type": "string" },
    "customLocationId": { "type": "string" },
    "tags":             { "type": "object" }
  },
  "resources": [
    {
      "type": "Microsoft.IoTOperations/instances/brokers",
      "apiVersion": "2024-11-01",
      "name": "[format('{0}/{1}', parameters('instanceName'), parameters('brokerName'))]",
      "extendedLocation": { "type": "CustomLocation", "name": "[parameters('customLocationId')]" },
      "tags": "[parameters('tags')]",
      "properties": { "memoryProfile": "Medium" },
      "dependsOn": [
        "[resourceId('Microsoft.IoTOperations/instances', parameters('instanceName'))]"
      ]
    }
  ],
  "outputs": {
    "brokerId": {
      "type": "string",
      "value": "[resourceId('Microsoft.IoTOperations/instances/brokers', parameters('instanceName'), parameters('brokerName'))]"
    }
  }
}
JSON

  parameters_content = jsonencode({
    instanceName     = { value = var.instance_name }
    brokerName       = { value = var.broker_name }
    customLocationId = { value = var.custom_location_id }
    tags             = { value = var.tags }
  })

  depends_on = [azurerm_resource_group_template_deployment.iotops_instance]
}

# ---------------- Broker Authentication (ARM: .../brokers/authentications@2024-11-01) ----------------
resource "azurerm_resource_group_template_deployment" "iotops_broker_auth" {
  name                = "${var.authorization_name}-deploy"
  resource_group_name = azurerm_resource_group.example.name
  deployment_mode     = "Incremental"

  template_content = <<JSON
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "instanceName":       { "type": "string" },
    "brokerName":         { "type": "string" },
    "authenticationName": { "type": "string" },
    "customLocationId":   { "type": "string" }
  },
  "resources": [
    {
      "type": "Microsoft.IoTOperations/instances/brokers/authentications",
      "apiVersion": "2024-11-01",
      "name": "[format('{0}/{1}/{2}', parameters('instanceName'), parameters('brokerName'), parameters('authenticationName'))]",
      "extendedLocation": { "type": "CustomLocation", "name": "[parameters('customLocationId')]" },
      "properties": {
        "authenticationMethods": [
          {
            "method": "ServiceAccountToken",
            "serviceAccountTokenSettings": { "audiences": ["audience1", "audience2"] }
          },
          {
            "method": "X509",
            "x509Settings": {
              "trustedClientCaCert": "example-ca-cert",
              "authorizationAttributes": { "building": "17", "floor": "1" }
            }
          },
          {
            "method": "Custom",
            "customSettings": {
              "auth": { "x509": { "secretRef": "example-secret" } },
              "caCertConfigMap": "example-ca-configmap",
              "endpoint": "https://example-auth-endpoint.com",
              "headers": {
                "X-Custom-Header": "example-value",
                "Authorization":   "Bearer token"
              }
            }
          }
        ]
      },
      "dependsOn": [
        "[resourceId('Microsoft.IoTOperations/instances/brokers', parameters('instanceName'), parameters('brokerName'))]"
      ]
    }
  ],
  "outputs": {
    "authenticationId": {
      "type": "string",
      "value": "[resourceId('Microsoft.IoTOperations/instances/brokers/authentications', parameters('instanceName'), parameters('brokerName'), parameters('authenticationName'))]"
    }
  }
}
JSON

  parameters_content = jsonencode({
    instanceName       = { value = var.instance_name }
    brokerName         = { value = var.broker_name }
    authenticationName = { value = var.authorization_name }
    customLocationId   = { value = var.custom_location_id }
  })

  depends_on = [azurerm_resource_group_template_deployment.iotops_broker]
}

# ---------------- Outputs ----------------
output "iotoperations_instance_id" {
  description = "ARM ID of the AIO instance."
  value       = jsondecode(azurerm_resource_group_template_deployment.iotops_instance.output_content).instanceId.value
}

output "iotoperations_broker_id" {
  description = "ARM ID of the AIO broker."
  value       = jsondecode(azurerm_resource_group_template_deployment.iotops_broker.output_content).brokerId.value
}

output "broker_authorization_id" {
  description = "ARM ID of the AIO broker authentication."
  value       = jsondecode(azurerm_resource_group_template_deployment.iotops_broker_auth.output_content).authenticationId.value
}

output "broker_authorization_name" {
  description = "Name of the AIO broker authentication."
  value       = var.authorization_name
}

output "resource_hierarchy" {
  description = "Complete resource hierarchy for the IoT Operations broker authentication."
  value = {
    subscription_id    = data.azurerm_client_config.current.subscription_id
    resource_group     = azurerm_resource_group.example.name
    instance_name      = var.instance_name
    broker_name        = var.broker_name
    authorization_name = var.authorization_name
  }
}
