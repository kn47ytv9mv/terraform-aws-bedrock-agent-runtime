variable "agent_runtime_name" {
  default     = null
  description = "Name of the agent runtime, which AWS requires. Valid characters are a-z, A-Z, 0-9 and underscore, it must begin with a letter, and it can be up to 48 characters. A hyphen is rejected, which is why this module offers no generated fallback — the family's random-UUID fallback contains hyphens."
}

variable "role_arn" {
  default     = null
  description = "ARN of the IAM role the runtime assumes while it executes, from terraform-aws-iam-role. The runtime needs this to reach Bedrock models and anything else it calls; the module does not create it."
}

variable "agent_runtime_artifact" {
  default     = null
  description = "What the runtime executes: either a container image, or code in S3. Set exactly one of container_uri and code. For code, entry_point is the command AWS runs, runtime is one of PYTHON_3_10 through PYTHON_3_14 or NODE_22, and s3 locates the archive."
  type = object({
    container_uri = optional(string)
    code = optional(object({
      entry_point = list(string)
      runtime     = string
      s3 = object({
        bucket     = string
        prefix     = string
        version_id = optional(string)
      })
    }))
  })

  validation {
    condition     = var.agent_runtime_artifact == null || ((var.agent_runtime_artifact.container_uri == null) != (var.agent_runtime_artifact.code == null))
    error_message = "Set exactly one of agent_runtime_artifact.container_uri or agent_runtime_artifact.code. AWS rejects both together and an artifact with neither."
  }
}

variable "description" {
  default     = null
  description = "Description of the agent runtime."
}

variable "environment_variables" {
  default     = null
  description = "Environment variables the runtime reads at startup. Do not put secrets here; they are readable to anyone who can describe the runtime. Reference a Secrets Manager secret from the code instead."
  type        = map(string)
}

variable "network_configuration" {
  default     = null
  description = "How the runtime itself reaches the network, which is separate from who may invoke it. 'PUBLIC' runs the agent in networking AWS manages, with outbound internet access and no reach into your VPC, and takes nothing else. 'VPC' attaches it to your subnets and security groups, so it reaches private resources and its egress follows your own routing, which means it needs a NAT gateway or interface endpoints to reach the internet. Both require a caller to be authorized by IAM or by custom_jwt_authorizer. AWS requires this block, so there is no default."
  type = object({
    network_mode    = string
    subnets         = optional(set(string))
    security_groups = optional(set(string))
  })

  validation {
    condition     = var.network_configuration != null
    error_message = "network_configuration is required. Set network_mode to 'PUBLIC' for an internet-facing runtime, or 'VPC' with subnets and security_groups to place it in your own network."
  }

  validation {
    condition     = var.network_configuration == null || contains(["PUBLIC", "VPC"], var.network_configuration.network_mode)
    error_message = "network_configuration.network_mode must be 'PUBLIC' or 'VPC'."
  }

  validation {
    condition     = try(var.network_configuration.network_mode, "") != "VPC" || (length(coalesce(var.network_configuration.subnets, [])) > 0 && length(coalesce(var.network_configuration.security_groups, [])) > 0)
    error_message = "network_mode 'VPC' requires both network_configuration.subnets and network_configuration.security_groups. A runtime with no subnet has nowhere to run."
  }

  validation {
    condition     = try(var.network_configuration.network_mode, "") != "PUBLIC" || (length(coalesce(var.network_configuration.subnets, [])) == 0 && length(coalesce(var.network_configuration.security_groups, [])) == 0)
    error_message = "network_mode 'PUBLIC' takes no subnets or security_groups. Set network_mode to 'VPC' to use them."
  }
}

variable "custom_jwt_authorizer" {
  default     = null
  description = "Authorizes callers by validating a JWT against an OIDC provider. discovery_url is the provider's well-known configuration document. Narrow the accepted tokens with allowed_audience, allowed_clients, or allowed_scopes; with none of them, any token the provider signs is accepted. If null, the runtime relies on IAM authorization alone. See the Design section for what this deliberately does not cover."
  type = object({
    discovery_url    = string
    allowed_audience = optional(set(string))
    allowed_clients  = optional(set(string))
    allowed_scopes   = optional(set(string))
  })
}

variable "filesystem_configuration" {
  default     = null
  description = "Storage mounted into the runtime. Set exactly one: efs_access_point and s3_files_access_point each take an access point ARN and the path to mount it at, and session_storage takes only a path and is scratch space that does not outlive the session. AWS permits one mount per runtime, not a combination."
  type = object({
    efs_access_point = optional(object({
      access_point_arn = string
      mount_path       = string
    }))
    s3_files_access_point = optional(object({
      access_point_arn = string
      mount_path       = string
    }))
    session_storage = optional(object({
      mount_path = string
    }))
  })

  validation {
    condition     = var.filesystem_configuration == null || length([for m in [var.filesystem_configuration.efs_access_point, var.filesystem_configuration.s3_files_access_point, var.filesystem_configuration.session_storage] : m if m != null]) == 1
    error_message = "Set exactly one of filesystem_configuration.efs_access_point, s3_files_access_point, or session_storage. AWS mounts one filesystem per runtime and rejects both a combination and an empty configuration."
  }
}

variable "lifecycle_configuration" {
  default     = null
  description = "How long a runtime session survives. idle_runtime_session_timeout ends a session that has gone quiet; max_lifetime ends one regardless of activity. Both are in seconds. If null, AWS applies its own defaults."
  type = object({
    idle_runtime_session_timeout = optional(number)
    max_lifetime                 = optional(number)
  })
}

variable "server_protocol" {
  default     = null
  description = "Protocol the runtime speaks, which AWS accepts as 'HTTP' or 'MCP'. 'MCP' exposes the runtime as a Model Context Protocol server. If null, AWS applies its own default."
}

variable "request_header_allowlist" {
  default     = null
  description = "Request headers forwarded to the runtime. Anything not listed is dropped before the runtime sees it, so a runtime reading a custom header needs that header named here."
  type        = set(string)
}

variable "tags" {
  default     = null
  description = "A map of tags to assign to the agent runtime."
}
