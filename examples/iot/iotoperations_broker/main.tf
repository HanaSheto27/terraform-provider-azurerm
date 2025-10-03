terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 3.0" }
  }
}

provider "azurerm" {
  features {}
}

# ---------- Vars ----------
variable "resource_group_name" { type = string }          # existing RG
variable "instance_name"       { type = string }          # existing AIO instance name

variable "broker_name" {
  type        = string
  default     = "example-broker"
  description = "Name for the broker to create under existing instance"
}

variable "custom_location_id"  { type = string }          # ARM ID of Custom Location

variable "memory_profile" {
  type        = string
  default     = "Medium"
  description = "Broker memory profile (string enum)."
}

# ---------- Data ----------
data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}

# ---------- Deploy Broker (child of existing Instance) ----------
resource "azurerm_resource_group_template_deployment" "iotops_broker" {
  name                = "${var.broker_name}-deploy"
  resource_group_name = data.azurerm_resource_group.rg.name
  deployment_mode     = "Incremental"

  template_content = <<JSON
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "instanceName":     { "type": "string" },
    "brokerName":       { "type": "string" },
    "customLocationId": { "type": "string" },
    "memoryProfile":    { "type": "string" }
  },
  "resources": [
    {
      "type": "Microsoft.IoTOperations/instances/brokers",
      "apiVersion": "2024-11-01",
      "name": "[format('{0}/{1}', parameters('instanceName'), parameters('brokerName'))]",
      "extendedLocation": {
        "type": "CustomLocation",
        "name": "[parameters('customLocationId')]"
      },
      "properties": {
        "memoryProfile": "[parameters('memoryProfile')]"
      }
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
    memoryProfile    = { value = var.memory_profile }
  })
}

output "broker_id" {
  value       = jsondecode(azurerm_resource_group_template_deployment.iotops_broker.output_content).brokerId.value
  description = "ARM ID of the Broker."
}
