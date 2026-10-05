# terraform-aws-bedrock-agent-runtime

Terraform module for a Bedrock AgentCore agent runtime — the managed
execution environment that hosts an agent, as a container image or as code
in S3, and holds a session open while the agent works.

## Cost

An agent runtime is billed for the compute a session consumes while it is
active, so a runtime with no sessions costs nothing to keep defined. Session
lifetime is therefore a cost control, not only a correctness setting: see
`lifecycle_configuration`.

Model inference is billed separately, against Bedrock, for every call the
agent makes. The runtime's own charge is for hosting, not for the thinking.

A VPC-mode runtime reaches AWS services through your subnets, so it can
incur NAT gateway data processing charges that a public runtime does not.
See AWS's [Bedrock pricing](https://aws.amazon.com/bedrock/pricing/) page
for current rates.

## Design

This module owns the agent runtime and nothing else. It does not create the
IAM role the runtime assumes, the container image it runs, or the S3 archive
holding its code — pass those in from [`terraform-aws-iam-role`](https://github.com/kn47ytv9mv/terraform-aws-iam-role),
[`terraform-aws-ecr-repository`](https://github.com/kn47ytv9mv/terraform-aws-ecr-repository), and [`terraform-aws-s3`](https://github.com/kn47ytv9mv/terraform-aws-s3) respectively.

Pair it with [`terraform-aws-bedrock-endpoint`](https://github.com/kn47ytv9mv/terraform-aws-bedrock-endpoint), which is how callers actually
reach a runtime. A runtime with no endpoint is deployed but unaddressable.

### Exactly one artifact, and exactly one mount

`agent_runtime_artifact` takes either a `container_uri` or a `code` block,
never both and never neither. `filesystem_configuration`, when set, takes
exactly one of an EFS access point from [`terraform-aws-efs-access-point`](https://github.com/kn47ytv9mv/terraform-aws-efs-access-point),
an S3 files access point from [`terraform-aws-s3-access-point`](https://github.com/kn47ytv9mv/terraform-aws-s3-access-point), or session
storage — AWS mounts one filesystem per runtime and rejects a combination.
Both rules are enforced at plan time rather than left to the apply.

### What the network modes mean, and what they do not

`network_mode` governs how the runtime itself reaches the network. It does
**not** govern who may invoke it.

`PUBLIC` runs the agent in networking AWS manages, with outbound access to
the public internet and no resources of yours involved. Nothing is created in
your VPC, and the runtime cannot reach anything private — a database on a
private subnet is unreachable from a `PUBLIC` runtime.

`VPC` attaches the runtime to the subnets and security groups you name, so it
can reach private resources and its egress follows your own routing. That
means a `VPC` runtime needing the internet needs a NAT gateway or interface
endpoints like any other workload, and reaches nothing at all if you give it
neither.

Invocation is authorized separately, and always. A caller needs IAM
permission to invoke the endpoint, or a token the `custom_jwt_authorizer`
accepts when one is configured. A `PUBLIC` runtime is therefore not an
internet-reachable agent — the name describes its egress, not its front door.

### Why this module does not default to private

The rest of this family defaults to the strict option — every guardrail
filter on at `HIGH`, IMDSv2 required, volumes encrypted, ECR tags immutable.
The consistent choice here would be `VPC`, and it is not available.

`VPC` is not a value a module can supply on its own. It is only meaningful
together with subnets and security groups, and those are facts about the
caller's network that this module has no way to know or invent. There is no
private default to fall back to, the way there is a stricter *setting* to
fall back to elsewhere in the family.

That leaves two options, and `PUBLIC` as a default is the worse one. It
would be a silent decision that the agent has internet egress and no reach
into your network — made by the module, invisibly, for every caller who did
not think about it. A required variable costs one line in every
configuration and makes the trade explicit, which is the same reasoning that
put an `enable_*` flag beside every log destination in this family rather
than inferring intent from a supplied value.

So the variable is required, and its error names both modes and what each
one gives up.

### Which values this module validates, and which it leaves to the provider

`network_mode` is validated here, because it has two values and the other
rules depend on which one is set. `server_protocol` and the code artifact's
`runtime` are not: both are lists AWS extends over time — a new Python
version appears as a new `runtime` — and a list hard-coded here would reject
a value the provider already accepts. The provider validates both and names
the valid values in its error, which is the better place for a list that
moves.

### Environment variables are visible

`environment_variables` are readable by anyone who can describe the runtime.
Put configuration there and nothing else; have the agent read a secret from
Secrets Manager at startup instead.

### Names reject hyphens

AWS accepts only letters, digits and underscore in an agent runtime name, it
must begin with a letter, and it caps at 48 characters. That rules out the
family's random-UUID fallback, which contains hyphens, so this module
generates no name — `agent_runtime_name` is simply required. The provider
reports the rule in full when a name breaks it, so this module adds no
validation of its own.

### Every change makes a new version

Editing a runtime produces a new `agent_runtime_version`. Endpoints may pin
to a version, so a change here does not reach a pinned endpoint until that
endpoint moves — which is the point of pinning. The `agent_runtime_version`
output is the version this revision produced.

### What this module does not cover

The JWT authorizer is supported in its common form: a discovery URL, and the
audiences, clients, or scopes to accept. Its private-endpoint and
custom-claim-matching forms are not modelled, because they nest four levels
deep and have no use in this family yet. Agent memory, browsers, code
interpreters, and gateways are separate AgentCore resources and separate
concerns.

## Usage

```hcl
module "runtime" {
  source = "kn47ytv9mv/bedrock-agent-runtime/aws"

  agent_runtime_name = "support_assistant"
  role_arn           = module.runtime_role.arn

  agent_runtime_artifact = {
    container_uri = "123456789012.dkr.ecr.us-east-1.amazonaws.com/support-assistant:latest"
  }

  network_configuration = {
    network_mode = "PUBLIC"
  }

  environment_variables = {
    MODEL_ID = "anthropic.claude-sonnet-4-5-20250929-v1:0"
  }

  tags = {
    Service = "support-assistant"
  }
}
```

Or directly from this repository:

```hcl
module "runtime" {
  source = "github.com/kn47ytv9mv/terraform-aws-bedrock-agent-runtime"

  agent_runtime_name = "support_assistant"
  role_arn           = module.runtime_role.arn

  agent_runtime_artifact = {
    container_uri = "123456789012.dkr.ecr.us-east-1.amazonaws.com/support-assistant:latest"
  }

  network_configuration = {
    network_mode = "PUBLIC"
  }
}
```

## Examples

<details>
<summary>A private runtime behind a JWT authorizer, with persistent storage</summary>

```hcl
module "runtime" {
  source = "kn47ytv9mv/bedrock-agent-runtime/aws"

  agent_runtime_name = "support_assistant"
  role_arn           = module.runtime_role.arn

  agent_runtime_artifact = {
    container_uri = "123456789012.dkr.ecr.us-east-1.amazonaws.com/support-assistant:latest"
  }

  network_configuration = {
    network_mode    = "VPC"
    subnets         = module.network.subnet_ids["private"]
    security_groups = [module.runtime_security_group.id]
  }

  custom_jwt_authorizer = {
    discovery_url   = "https://example.auth0.com/.well-known/openid-configuration"
    allowed_clients = ["agent-cli"]
  }

  filesystem_configuration = {
    efs_access_point = {
      access_point_arn = module.state_access_point.arn
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
```

</details>

<details>
<summary>A runtime from code in S3 rather than a container image</summary>

```hcl
module "runtime" {
  source = "kn47ytv9mv/bedrock-agent-runtime/aws"

  agent_runtime_name = "support_assistant"
  role_arn           = module.runtime_role.arn

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

  network_configuration = {
    network_mode = "PUBLIC"
  }
}
```

`runtime` accepts `PYTHON_3_10` through `PYTHON_3_14` and `NODE_22`.

</details>

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.3 |
| aws | ~> 6.61 |

## Providers

| Name | Version |
|---|---|
| aws | ~> 6.61 |

## Inputs

| Name | Description | Default | Required |
|---|---|---|---|
| agent_runtime_name | Name of the agent runtime. Letters, digits and underscore only, beginning with a letter, up to 48 characters. | `null` | no |
| role_arn | ARN of the IAM role the runtime assumes while it executes. | `null` | no |
| agent_runtime_artifact | What the runtime executes: exactly one of a container image or code in S3. | `null` | no |
| description | Description of the agent runtime. | `null` | no |
| environment_variables | Environment variables the runtime reads at startup. Not for secrets. | `null` | no |
| network_configuration | How the runtime reaches the network. Required — `PUBLIC`, or `VPC` with subnets and security groups. | `null` | **yes** |
| custom_jwt_authorizer | Authorizes callers by validating a JWT against an OIDC provider. | `null` | no |
| filesystem_configuration | Storage mounted into the runtime, from [`terraform-aws-efs-access-point`](https://github.com/kn47ytv9mv/terraform-aws-efs-access-point) or [`terraform-aws-s3-access-point`](https://github.com/kn47ytv9mv/terraform-aws-s3-access-point). Exactly one mount. | `null` | no |
| lifecycle_configuration | How long a runtime session survives, in seconds. | `null` | no |
| server_protocol | Protocol the runtime speaks: `HTTP`, `MCP`, or `A2A`. | `null` | no |
| request_header_allowlist | Request headers forwarded to the runtime. Anything unlisted is dropped. | `null` | no |
| tags | A map of tags to assign to the agent runtime. | `null` | no |

## Outputs

| Name | Description |
|---|---|
| arn | The ARN of the agent runtime. |
| agent_runtime_id | The ID of the agent runtime, which is what [`terraform-aws-bedrock-endpoint`](https://github.com/kn47ytv9mv/terraform-aws-bedrock-endpoint) takes as `agent_runtime_id`. |
| name | The name of the agent runtime. |
| agent_runtime_version | The version AWS assigned to this revision of the runtime. |
| workload_identity_arn | The ARN of the workload identity AWS created for the runtime. |

## License

MIT — see [LICENSE.md](LICENSE.md).
