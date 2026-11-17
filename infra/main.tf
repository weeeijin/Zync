locals {
  name           = "${var.project}-${var.environment}"
  create_dns     = var.domain_name != "" && var.route53_zone_id != ""
  create_alarms  = var.alarm_email != ""
  app_directory  = "/home/ubuntu/Zync"
  backup_bucket  = "${local.name}-backups-${data.aws_caller_identity.current.account_id}"
  public_ingress = { http = 80, https = 443 }
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# ── Network ──────────────────────────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.name}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name}-igw" }
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidr
  availability_zone = data.aws_availability_zones.available.names[0]
  # No automatic public IPs — the server gets a stable Elastic IP instead
  map_public_ip_on_launch = false

  tags = { Name = "${local.name}-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${local.name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Lock down the VPC's default security group so nothing uses it by accident
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name}-default-locked" }
}

# ── Firewall: only HTTP/HTTPS public, SSH from allow-listed CIDRs ───────────
resource "aws_security_group" "app" {
  name        = "${local.name}-app"
  description = "Zync app server: public web traffic via Caddy, restricted SSH"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-app" }
}

# trivy:ignore:AVD-AWS-0107 — public web server: 80/443 must be reachable by everyone
resource "aws_vpc_security_group_ingress_rule" "web_ipv4" {
  for_each = local.public_ingress

  security_group_id = aws_security_group.app.id
  description       = "Public ${upper(each.key)} to Caddy"
  ip_protocol       = "tcp"
  from_port         = each.value
  to_port           = each.value
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "http3" {
  security_group_id = aws_security_group.app.id
  description       = "HTTP/3 (QUIC) to Caddy"
  ip_protocol       = "udp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0" # trivy:ignore:AVD-AWS-0107 — public web server
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = toset(var.ssh_allowed_cidrs)

  security_group_id = aws_security_group.app.id
  description       = "SSH from allow-listed admin/CI range"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = each.value
}

# trivy:ignore:AVD-AWS-0104 — server must reach GHCR, Docker Hub, Let's Encrypt, OS mirrors and the GLM API
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.app.id
  description       = "Outbound internet (image pulls, ACME, LLM API, updates)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ── VPC Flow Logs: record rejected connections (port scans, blocked attacks) ─
resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/vpc/${local.name}/flow-logs"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.main.arn
}

data "aws_iam_policy_document" "flow_logs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  name               = "${local.name}-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume.json
}

data "aws_iam_policy_document" "flow_logs" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.flow_logs.arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  name   = "write-flow-logs"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs.json
}

resource "aws_flow_log" "main" {
  vpc_id          = aws_vpc.main.id
  traffic_type    = "REJECT"
  log_destination = aws_cloudwatch_log_group.flow_logs.arn
  iam_role_arn    = aws_iam_role.flow_logs.arn
}
