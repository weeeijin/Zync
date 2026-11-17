# Infrastructure-level alarms. Application metrics/alerts live in the
# Prometheus + Grafana stack (monitoring/); these cover "the box itself is sick".

# Auto-recover the instance onto healthy hardware if AWS detects a host failure.
# Always on — it needs no notification target.
resource "aws_cloudwatch_metric_alarm" "system_recovery" {
  alarm_name          = "${local.name}-system-status-recover"
  alarm_description   = "Underlying AWS host failed — automatically recover the instance"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_System"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  dimensions          = { InstanceId = aws_instance.app.id }
  alarm_actions = concat(
    ["arn:aws:automate:${var.aws_region}:ec2:recover"],
    aws_sns_topic.alerts[*].arn,
  )
}

resource "aws_sns_topic" "alerts" {
  count             = local.create_alarms ? 1 : 0
  name              = "${local.name}-alerts"
  kms_master_key_id = aws_kms_key.main.arn
}

resource "aws_sns_topic_subscription" "email" {
  count     = local.create_alarms ? 1 : 0
  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

resource "aws_cloudwatch_metric_alarm" "instance_status" {
  count               = local.create_alarms ? 1 : 0
  alarm_name          = "${local.name}-instance-status"
  alarm_description   = "Instance status check failing (OS hung, out of memory, disk full...)"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_Instance"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  dimensions          = { InstanceId = aws_instance.app.id }
  alarm_actions       = [aws_sns_topic.alerts[0].arn]
  ok_actions          = [aws_sns_topic.alerts[0].arn]
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  count               = local.create_alarms ? 1 : 0
  alarm_name          = "${local.name}-cpu-high"
  alarm_description   = "CPU above 85% for 15 minutes"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 85
  comparison_operator = "GreaterThanThreshold"
  dimensions          = { InstanceId = aws_instance.app.id }
  alarm_actions       = [aws_sns_topic.alerts[0].arn]
  ok_actions          = [aws_sns_topic.alerts[0].arn]
}

# ── Cost guard: email before the bill surprises you ─────────────────────────
resource "aws_budgets_budget" "monthly" {
  count = local.create_alarms && var.monthly_budget_usd > 0 ? 1 : 0

  name         = "${local.name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alarm_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alarm_email]
  }
}
