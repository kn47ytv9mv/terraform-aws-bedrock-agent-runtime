resource "aws_bedrockagentcore_agent_runtime" "resource" {
  agent_runtime_name = var.agent_runtime_name
  role_arn           = var.role_arn
  description        = var.description

  environment_variables   = var.environment_variables
  lifecycle_configuration = var.lifecycle_configuration[*]

  dynamic "agent_runtime_artifact" {
    for_each = var.agent_runtime_artifact[*]

    content {
      dynamic "container_configuration" {
        for_each = agent_runtime_artifact.value.container_uri[*]

        content {
          container_uri = container_configuration.value
        }
      }

      dynamic "code_configuration" {
        for_each = agent_runtime_artifact.value.code[*]

        content {
          entry_point = code_configuration.value.entry_point
          runtime     = code_configuration.value.runtime

          code {
            s3 {
              bucket     = code_configuration.value.s3.bucket
              prefix     = code_configuration.value.s3.prefix
              version_id = code_configuration.value.s3.version_id
            }
          }
        }
      }
    }
  }

  dynamic "network_configuration" {
    for_each = var.network_configuration[*]

    content {
      network_mode = network_configuration.value.network_mode

      dynamic "network_mode_config" {
        for_each = length(coalesce(network_configuration.value.subnets, [])) > 0 ? [network_configuration.value] : []

        content {
          subnets         = network_mode_config.value.subnets
          security_groups = network_mode_config.value.security_groups
        }
      }
    }
  }

  dynamic "authorizer_configuration" {
    for_each = var.custom_jwt_authorizer[*]

    content {
      custom_jwt_authorizer {
        discovery_url    = authorizer_configuration.value.discovery_url
        allowed_audience = authorizer_configuration.value.allowed_audience
        allowed_clients  = authorizer_configuration.value.allowed_clients
        allowed_scopes   = authorizer_configuration.value.allowed_scopes
      }
    }
  }

  dynamic "filesystem_configuration" {
    for_each = var.filesystem_configuration[*]

    content {
      dynamic "efs_access_point" {
        for_each = filesystem_configuration.value.efs_access_point[*]

        content {
          access_point_arn = efs_access_point.value.access_point_arn
          mount_path       = efs_access_point.value.mount_path
        }
      }

      dynamic "s3_files_access_point" {
        for_each = filesystem_configuration.value.s3_files_access_point[*]

        content {
          access_point_arn = s3_files_access_point.value.access_point_arn
          mount_path       = s3_files_access_point.value.mount_path
        }
      }

      dynamic "session_storage" {
        for_each = filesystem_configuration.value.session_storage[*]

        content {
          mount_path = session_storage.value.mount_path
        }
      }
    }
  }

  dynamic "protocol_configuration" {
    for_each = var.server_protocol[*]

    content {
      server_protocol = protocol_configuration.value
    }
  }

  dynamic "request_header_configuration" {
    for_each = var.request_header_allowlist == null ? [] : [var.request_header_allowlist]

    content {
      request_header_allowlist = request_header_configuration.value
    }
  }

  tags = var.tags
}

output "arn" {
  description = "The ARN of the agent runtime."
  value       = aws_bedrockagentcore_agent_runtime.resource.agent_runtime_arn
}

output "agent_runtime_id" {
  description = "The ID of the agent runtime. This is what terraform-aws-bedrock-endpoint takes as agent_runtime_id — an endpoint identifies its runtime by ID, not by ARN."
  value       = aws_bedrockagentcore_agent_runtime.resource.agent_runtime_id
}

output "name" {
  description = "The name of the agent runtime."
  value       = aws_bedrockagentcore_agent_runtime.resource.agent_runtime_name
}

output "agent_runtime_version" {
  description = "The version AWS assigned to this revision of the runtime. Pass it to an endpoint's agent_runtime_version to pin that endpoint to this revision."
  value       = aws_bedrockagentcore_agent_runtime.resource.agent_runtime_version
}

output "workload_identity_arn" {
  description = "The ARN of the workload identity AWS created for the runtime, which is the principal it presents to other services."
  value       = try(one(aws_bedrockagentcore_agent_runtime.resource.workload_identity_details).workload_identity_arn, null)
}
