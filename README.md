# unicycling-infra

Shared Terraform modules for the unicycling ECS apps. Each app pins a git tag and calls the modules from its own
Terraform root.

## Modules

- `modules/alb-ingress`: public ALB, HTTP and HTTPS listeners, ACM certificate, Route53 records, and the ECS and legacy
  EC2 target groups. The ECS weight (`ecs_traffic_weight`) splits traffic during cutover.
- `modules/ecs-app`: ECS cluster, web and sidekiq task definitions and services, IAM roles, security groups, log groups,
  and EventBridge scheduled tasks. Sidecars, extra environment variables, secrets, and scheduled commands are inputs.

Each app keeps what is specific to it (for example, IAM policy for its IAM user) in its own root.

## Usage

```hcl
module "alb" {
  source = "git::https://github.com/rdunlop/unicycling-infra.git//modules/alb-ingress?ref=v0.1.0"
  # ...
}

module "ecs_app" {
  source = "git::https://github.com/rdunlop/unicycling-infra.git//modules/ecs-app?ref=v0.1.0"
  # ...
}
```

See `examples/registration/main.tf` for a complete call. It is used to validate the modules and is not meant to be
applied.

## Versioning

- Tags are semver (`v0.1.0`). A breaking change to an input or resource name gets a new major or minor version.
- Projects bump the `ref` deliberately, then run `terraform init -upgrade` and a plan, and check that the plan shows
  only the intended changes before applying.
- Resource addresses matter. Renaming a resource inside a module (for example `aws_route53_record.registration` became
  `aws_route53_record.alb`) needs a `moved` block in the calling project, or the plan will destroy and recreate it.

## Validating

```bash
terraform -chdir=examples/registration init -backend=false
terraform -chdir=examples/registration validate
terraform fmt -check -recursive
```

## Status

v0.4.0 changes two things from v0.3.0. Both are optional, and the defaults keep the existing behaviour:

- `ecs-app`: `redis_security_group_id` is optional. Pass `null` for apps that do not use the shared ElastiCache
  cluster, and no Redis ingress rule is created.
- `ecs-app`: `sidekiq_enabled` (default `true`). Set `false` for apps with no sidekiq worker. Then the sidekiq log group,
  task definition and service are not created, and `sidekiq_service_name` is null.

Both use `count`. `moved.tf` maps the existing addresses to `[0]`, so apps that already have these resources (registration,
rulebook) keep their state and a ref bump does not plan a replacement.

v0.2.0 changes two things from v0.1.0:

- `alb-ingress`: the legacy EC2 target group, its instance attachment and its security group rule are now optional
  (`legacy_ec2`). Pass `null` once EC2 is gone. The listener then forwards 100% to ECS. Apps still on EC2 pass the
  instance and security group IDs and keep the weighted split. Note that the attachment is created by Terraform, not
  imported, because `aws_lb_target_group_attachment` does not support import. Re-registering an existing target is a
  no-op in AWS, so the plan shows "create" harmlessly on first adoption.
- `ecs-app`: container definitions now include the empty `mountPoints`, `portMappings`, `systemControls`, `volumesFrom`
  and `environment` fields, and `hostPort` on the web port, which ECS fills in on its own. Without them, every plan
  shows a task-definition replacement.

Continuing work (CI scripts, release hooks, `skip_destroy`, removing `ignore_changes` on task definitions) is planned
in later versions.
