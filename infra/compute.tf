# ── AMI: latest Ubuntu 24.04 LTS published by Canonical ─────────────────────
data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

resource "aws_key_pair" "deploy" {
  key_name   = "${local.name}-deploy"
  public_key = var.ssh_public_key
}

# ── IAM: Session Manager access + write-only-ish access to the backup bucket ─
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "${local.name}-app"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

# Shell access through AWS Systems Manager — works even if SSH is locked down
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "backups" {
  statement {
    sid       = "ListBackups"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.backups.arn]
  }
  statement {
    sid       = "ReadWriteBackups"
    actions   = ["s3:PutObject", "s3:GetObject"]
    resources = ["${aws_s3_bucket.backups.arn}/*"]
  }
  statement {
    sid       = "UseBackupKey"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [aws_kms_key.main.arn]
  }
}

resource "aws_iam_role_policy" "backups" {
  name   = "backups"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.backups.json
}

resource "aws_iam_instance_profile" "app" {
  name = "${local.name}-app"
  role = aws_iam_role.app.name
}

# ── App server ───────────────────────────────────────────────────────────────
resource "aws_instance" "app" {
  ami                    = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.app.id]
  key_name               = aws_key_pair.deploy.key_name
  iam_instance_profile   = aws_iam_instance_profile.app.name
  monitoring             = true

  user_data = templatefile("${path.module}/templates/user_data.sh.tftpl", {
    app_directory = local.app_directory
    backup_bucket = aws_s3_bucket.backups.bucket
    aws_region    = var.aws_region
  })
  user_data_replace_on_change = false

  # IMDSv2 only — blocks SSRF-style credential theft from the metadata service
  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2 # containers may need IMDS for the instance role
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    encrypted             = true
    kms_key_id            = aws_kms_key.main.arn
    delete_on_termination = true
    # Explicit (default_tags don't reliably reach root volumes); DLM copies
    # these onto snapshots, which demo-down.sh uses to clean them up
    tags = {
      Name        = "${local.name}-root"
      Backup      = "daily"
      Project     = var.project
      Environment = var.environment
    }
  }

  tags = { Name = "${local.name}-app" }

  lifecycle {
    # A new AMI release must not silently replace the server (and its data)
    ignore_changes = [ami, user_data]
  }
}

resource "aws_eip" "app" {
  domain   = "vpc"
  instance = aws_instance.app.id
  tags     = { Name = "${local.name}-eip" }

  depends_on = [aws_internet_gateway.main]
}

# ── DNS (optional) ───────────────────────────────────────────────────────────
resource "aws_route53_record" "app" {
  count = local.create_dns ? 1 : 0

  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"
  ttl     = 300
  records = [aws_eip.app.public_ip]
}
