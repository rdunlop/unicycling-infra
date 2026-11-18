# State moves for resources that gained a count. Callers that already had these resources
# (for example registration and rulebook, which run sidekiq) keep their state addresses,
# so bumping the module ref does not plan a replacement. Remove in a later major version.

moved {
  from = aws_security_group_rule.redis_from_ecs
  to   = aws_security_group_rule.redis_from_ecs[0]
}

moved {
  from = aws_cloudwatch_log_group.sidekiq
  to   = aws_cloudwatch_log_group.sidekiq[0]
}

moved {
  from = aws_ecs_task_definition.sidekiq
  to   = aws_ecs_task_definition.sidekiq[0]
}

moved {
  from = aws_ecs_service.sidekiq
  to   = aws_ecs_service.sidekiq[0]
}
