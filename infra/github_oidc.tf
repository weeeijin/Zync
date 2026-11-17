# Keyless AWS access for GitHub Actions (OIDC). The deploy job assumes this
# role for a few minutes to open SSH to *its own* runner IP, then closes it —
# so port 22 never has to be open to all of GitHub's IP ranges.

variable "github_repository" {
  description = "owner/repo allowed to assume the deploy role"
  type        = string
  default     = "weeeijin/Zync"
}

variable "create_github_oidc_provider" {
  description = "Set false if the account already has the GitHub OIDC provider"
  type        = bool
  default     = true
}

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_github_oidc_provider ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  github_oidc_arn = (var.create_github_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
  : data.aws_iam_openid_connect_provider.github[0].arn)
}

data "aws_iam_policy_document" "github_deploy_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Only jobs running in this repo's "production" environment
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:environment:${var.environment}"]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name                 = "${local.name}-github-deploy"
  assume_role_policy   = data.aws_iam_policy_document.github_deploy_assume.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "github_deploy" {
  statement {
    sid       = "ToggleSshForRunner"
    actions   = ["ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress"]
    resources = [aws_security_group.app.arn]
  }
  statement {
    sid       = "Describe"
    actions   = ["ec2:DescribeSecurityGroups", "ec2:DescribeSecurityGroupRules"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  name   = "toggle-ssh"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy.json
}

output "github_deploy_role_arn" {
  description = "Set as the AWS_DEPLOY_ROLE_ARN GitHub variable"
  value       = aws_iam_role.github_deploy.arn
}

output "security_group_id" {
  description = "Set as the AWS_SECURITY_GROUP_ID GitHub variable"
  value       = aws_security_group.app.id
}
