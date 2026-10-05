mock_provider "aws" {
  mock_resource "aws_bedrockagentcore_agent_runtime" {
    defaults = {
      agent_runtime_arn     = "arn:aws:bedrock-agentcore:us-east-1:123456789012:runtime/example"
      agent_runtime_id      = "example-abc123"
      agent_runtime_version = "1"
    }
  }
}

run "an_artifact_with_both_a_container_and_code_is_rejected" {
  command = plan

  variables {
    agent_runtime_name = "example"
    role_arn           = "arn:aws:iam::123456789012:role/example"

    network_configuration = { network_mode = "PUBLIC" }

    agent_runtime_artifact = {
      container_uri = "123456789012.dkr.ecr.us-east-1.amazonaws.com/agent:latest"

      code = {
        entry_point = ["python", "main.py"]
        runtime     = "PYTHON_3_12"
        s3          = { bucket = "example", prefix = "agent.zip" }
      }
    }
  }

  expect_failures = [var.agent_runtime_artifact]
}

run "an_artifact_with_neither_a_container_nor_code_is_rejected" {
  command = plan

  variables {
    agent_runtime_name     = "example"
    role_arn               = "arn:aws:iam::123456789012:role/example"
    agent_runtime_artifact = {}
    network_configuration  = { network_mode = "PUBLIC" }
  }

  expect_failures = [var.agent_runtime_artifact]
}

run "a_missing_network_configuration_is_rejected" {
  command = plan

  variables {
    agent_runtime_name = "example"
    role_arn           = "arn:aws:iam::123456789012:role/example"

  }

  expect_failures = [var.network_configuration]
}

run "an_unknown_network_mode_is_rejected" {
  command = plan

  variables {
    agent_runtime_name = "example"
    role_arn           = "arn:aws:iam::123456789012:role/example"

    network_configuration = { network_mode = "PRIVATE" }
  }

  expect_failures = [var.network_configuration]
}

run "a_vpc_network_mode_without_subnets_is_rejected" {
  command = plan

  variables {
    agent_runtime_name = "example"
    role_arn           = "arn:aws:iam::123456789012:role/example"

    network_configuration = {
      network_mode    = "VPC"
      security_groups = ["sg-aaaaaaaa"]
    }
  }

  expect_failures = [var.network_configuration]
}

run "a_public_network_mode_with_subnets_is_rejected" {
  command = plan

  variables {
    agent_runtime_name = "example"
    role_arn           = "arn:aws:iam::123456789012:role/example"

    network_configuration = {
      network_mode    = "PUBLIC"
      subnets         = ["subnet-aaaaaaaa"]
      security_groups = ["sg-aaaaaaaa"]
    }
  }

  expect_failures = [var.network_configuration]
}

run "two_filesystem_mounts_are_rejected" {
  command = plan

  variables {
    agent_runtime_name = "example"
    role_arn           = "arn:aws:iam::123456789012:role/example"

    network_configuration = { network_mode = "PUBLIC" }

    agent_runtime_artifact = {
      container_uri = "123456789012.dkr.ecr.us-east-1.amazonaws.com/agent:latest"
    }

    filesystem_configuration = {
      efs_access_point = {
        access_point_arn = "arn:aws:elasticfilesystem:us-east-1:123456789012:access-point/fsap-aaaaaaaa"
        mount_path       = "/mnt/state"
      }

      session_storage = {
        mount_path = "/mnt/scratch"
      }
    }
  }

  expect_failures = [var.filesystem_configuration]
}

run "a_container_artifact_omits_the_code_configuration" {
  command = plan

  variables {
    agent_runtime_name = "example"
    role_arn           = "arn:aws:iam::123456789012:role/example"

    network_configuration = { network_mode = "PUBLIC" }

    agent_runtime_artifact = {
      container_uri = "123456789012.dkr.ecr.us-east-1.amazonaws.com/agent:latest"
    }
  }

  assert {
    condition     = length(one(aws_bedrockagentcore_agent_runtime.resource.agent_runtime_artifact).container_configuration) == 1
    error_message = "A container artifact should produce one container_configuration block."
  }

  assert {
    condition     = length(one(aws_bedrockagentcore_agent_runtime.resource.agent_runtime_artifact).code_configuration) == 0
    error_message = "A container artifact should produce no code_configuration block."
  }
}

run "a_code_artifact_carries_its_s3_location" {
  command = plan

  variables {
    agent_runtime_name = "example"
    role_arn           = "arn:aws:iam::123456789012:role/example"

    network_configuration = { network_mode = "PUBLIC" }

    agent_runtime_artifact = {
      code = {
        entry_point = ["python", "main.py"]
        runtime     = "PYTHON_3_12"
        s3          = { bucket = "example-artifacts", prefix = "agent.zip", version_id = "3HL4kqtJlcpXroDTDmjVBH40Nrjfkd" }
      }
    }
  }

  assert {
    condition     = one(one(aws_bedrockagentcore_agent_runtime.resource.agent_runtime_artifact).code_configuration).runtime == "PYTHON_3_12"
    error_message = "A code artifact should pass its runtime through."
  }

  assert {
    condition     = one(one(one(one(aws_bedrockagentcore_agent_runtime.resource.agent_runtime_artifact).code_configuration).code).s3).bucket == "example-artifacts"
    error_message = "A code artifact should pass its S3 bucket through."
  }
}

run "a_public_runtime_omits_the_network_mode_config" {
  command = plan

  variables {
    agent_runtime_name = "example"
    role_arn           = "arn:aws:iam::123456789012:role/example"

    agent_runtime_artifact = {
      container_uri = "123456789012.dkr.ecr.us-east-1.amazonaws.com/agent:latest"
    }

    network_configuration = {
      network_mode = "PUBLIC"
    }
  }

  assert {
    condition     = length(one(aws_bedrockagentcore_agent_runtime.resource.network_configuration).network_mode_config) == 0
    error_message = "A public runtime takes no subnets, so network_mode_config should be omitted entirely."
  }
}

run "a_vpc_runtime_carries_its_subnets_and_security_groups" {
  command = plan

  variables {
    agent_runtime_name = "example"
    role_arn           = "arn:aws:iam::123456789012:role/example"

    agent_runtime_artifact = {
      container_uri = "123456789012.dkr.ecr.us-east-1.amazonaws.com/agent:latest"
    }

    network_configuration = {
      network_mode    = "VPC"
      subnets         = ["subnet-aaaaaaaa", "subnet-bbbbbbbb"]
      security_groups = ["sg-aaaaaaaa"]
    }
  }

  assert {
    condition     = one(one(aws_bedrockagentcore_agent_runtime.resource.network_configuration).network_mode_config).subnets == toset(["subnet-aaaaaaaa", "subnet-bbbbbbbb"])
    error_message = "A VPC runtime should pass its subnets through."
  }
}

run "optional_blocks_are_absent_by_default" {
  command = plan

  variables {
    agent_runtime_name = "example"
    role_arn           = "arn:aws:iam::123456789012:role/example"

    network_configuration = { network_mode = "PUBLIC" }

    agent_runtime_artifact = {
      container_uri = "123456789012.dkr.ecr.us-east-1.amazonaws.com/agent:latest"
    }
  }

  assert {
    condition     = length(aws_bedrockagentcore_agent_runtime.resource.authorizer_configuration) == 0
    error_message = "With no custom_jwt_authorizer the authorizer_configuration block should be omitted."
  }

  assert {
    condition     = length(aws_bedrockagentcore_agent_runtime.resource.filesystem_configuration) == 0
    error_message = "With no filesystem_configuration the block should be omitted."
  }

  assert {
    condition     = length(aws_bedrockagentcore_agent_runtime.resource.protocol_configuration) == 0
    error_message = "With no server_protocol the protocol_configuration block should be omitted."
  }

  assert {
    condition     = length(aws_bedrockagentcore_agent_runtime.resource.request_header_configuration) == 0
    error_message = "With no request_header_allowlist the request_header_configuration block should be omitted."
  }

  assert {
    condition     = length(aws_bedrockagentcore_agent_runtime.resource.lifecycle_configuration) == 0
    error_message = "With no lifecycle_configuration the attribute should be an empty list rather than a null entry."
  }
}

run "a_jwt_authorizer_narrows_the_accepted_tokens" {
  command = plan

  variables {
    agent_runtime_name = "example"
    role_arn           = "arn:aws:iam::123456789012:role/example"

    network_configuration = { network_mode = "PUBLIC" }

    agent_runtime_artifact = {
      container_uri = "123456789012.dkr.ecr.us-east-1.amazonaws.com/agent:latest"
    }

    custom_jwt_authorizer = {
      discovery_url    = "https://example.auth0.com/.well-known/openid-configuration"
      allowed_audience = ["https://agent.example.com"]
    }
  }

  assert {
    condition     = one(one(aws_bedrockagentcore_agent_runtime.resource.authorizer_configuration).custom_jwt_authorizer).discovery_url == "https://example.auth0.com/.well-known/openid-configuration"
    error_message = "A JWT authorizer should pass its discovery URL through."
  }

  assert {
    condition     = one(one(aws_bedrockagentcore_agent_runtime.resource.authorizer_configuration).custom_jwt_authorizer).allowed_audience == toset(["https://agent.example.com"])
    error_message = "A JWT authorizer should pass its allowed audience through."
  }
}

run "a_single_filesystem_mount_is_applied" {
  command = plan

  variables {
    agent_runtime_name = "example"
    role_arn           = "arn:aws:iam::123456789012:role/example"

    network_configuration = { network_mode = "PUBLIC" }

    agent_runtime_artifact = {
      container_uri = "123456789012.dkr.ecr.us-east-1.amazonaws.com/agent:latest"
    }

    filesystem_configuration = {
      efs_access_point = {
        access_point_arn = "arn:aws:elasticfilesystem:us-east-1:123456789012:access-point/fsap-aaaaaaaa"
        mount_path       = "/mnt/state"
      }
    }
  }

  assert {
    condition     = one(one(aws_bedrockagentcore_agent_runtime.resource.filesystem_configuration).efs_access_point).mount_path == "/mnt/state"
    error_message = "An EFS access point should mount at the path given."
  }

  assert {
    condition     = length(one(aws_bedrockagentcore_agent_runtime.resource.filesystem_configuration).s3_files_access_point) == 0
    error_message = "An unset s3_files_access_point should produce no block."
  }
}

run "lifecycle_and_protocol_pass_through" {
  command = plan

  variables {
    agent_runtime_name = "example"
    role_arn           = "arn:aws:iam::123456789012:role/example"

    network_configuration = { network_mode = "PUBLIC" }

    agent_runtime_artifact = {
      container_uri = "123456789012.dkr.ecr.us-east-1.amazonaws.com/agent:latest"
    }

    server_protocol          = "MCP"
    request_header_allowlist = ["X-Tenant-Id"]

    lifecycle_configuration = {
      idle_runtime_session_timeout = 900
      max_lifetime                 = 28800
    }
  }

  assert {
    condition     = one(aws_bedrockagentcore_agent_runtime.resource.protocol_configuration).server_protocol == "MCP"
    error_message = "server_protocol should pass through to protocol_configuration."
  }

  assert {
    condition     = one(aws_bedrockagentcore_agent_runtime.resource.lifecycle_configuration).max_lifetime == 28800
    error_message = "lifecycle_configuration should pass through."
  }

  assert {
    condition     = one(aws_bedrockagentcore_agent_runtime.resource.request_header_configuration).request_header_allowlist == toset(["X-Tenant-Id"])
    error_message = "request_header_allowlist should pass through."
  }
}

run "readme_container_example" {
  command = plan

  variables {
    agent_runtime_name = "support_assistant"
    role_arn           = "arn:aws:iam::123456789012:role/example"

    network_configuration = { network_mode = "PUBLIC" }

    agent_runtime_artifact = {
      container_uri = "123456789012.dkr.ecr.us-east-1.amazonaws.com/support-assistant:latest"
    }

    environment_variables = {
      MODEL_ID = "anthropic.claude-sonnet-4-5-20250929-v1:0"
    }

    tags = {
      Service = "support-assistant"
    }
  }

  assert {
    condition     = aws_bedrockagentcore_agent_runtime.resource.agent_runtime_name == "support_assistant"
    error_message = "The README's container example should plan."
  }
}

run "readme_github_source_example" {
  command = plan

  variables {
    agent_runtime_name = "support_assistant"
    role_arn           = "arn:aws:iam::123456789012:role/example"

    network_configuration = { network_mode = "PUBLIC" }

    agent_runtime_artifact = {
      container_uri = "123456789012.dkr.ecr.us-east-1.amazonaws.com/support-assistant:latest"
    }
  }

  assert {
    condition     = length(one(aws_bedrockagentcore_agent_runtime.resource.agent_runtime_artifact).container_configuration) == 1
    error_message = "The README's GitHub-source example should plan."
  }
}

run "readme_private_vpc_example" {
  command = plan

  variables {
    agent_runtime_name = "support_assistant"
    role_arn           = "arn:aws:iam::123456789012:role/example"

    agent_runtime_artifact = {
      container_uri = "123456789012.dkr.ecr.us-east-1.amazonaws.com/support-assistant:latest"
    }

    network_configuration = {
      network_mode    = "VPC"
      subnets         = ["subnet-aaaaaaaa", "subnet-bbbbbbbb"]
      security_groups = ["sg-aaaaaaaa"]
    }

    custom_jwt_authorizer = {
      discovery_url   = "https://example.auth0.com/.well-known/openid-configuration"
      allowed_clients = ["agent-cli"]
    }

    filesystem_configuration = {
      efs_access_point = {
        access_point_arn = "arn:aws:elasticfilesystem:us-east-1:123456789012:access-point/fsap-aaaaaaaa"
        mount_path       = "/mnt/state"
      }
    }

    lifecycle_configuration = {
      idle_runtime_session_timeout = 900
    }

    tags = {
      Service = "support-assistant"
    }
  }

  assert {
    condition     = length(aws_bedrockagentcore_agent_runtime.resource.authorizer_configuration) == 1
    error_message = "The README's private example should plan with its authorizer."
  }
}

run "readme_code_artifact_example" {
  command = plan

  variables {
    agent_runtime_name = "support_assistant"
    role_arn           = "arn:aws:iam::123456789012:role/example"

    network_configuration = { network_mode = "PUBLIC" }

    agent_runtime_artifact = {
      code = {
        entry_point = ["python", "main.py"]
        runtime     = "PYTHON_3_12"

        s3 = {
          bucket = "example-artifacts"
          prefix = "support-assistant/agent.zip"
        }
      }
    }
  }

  assert {
    condition     = length(one(aws_bedrockagentcore_agent_runtime.resource.agent_runtime_artifact).code_configuration) == 1
    error_message = "The README's code example should plan."
  }
}
