# Secrets module (PETPLAT-33, PETPLAT-37)
# Manages non-RDS secrets in AWS Secrets Manager and the ESO IRSA role.
# RDS credentials are owned by the RDS module (PETPLAT-23) — not created here.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  tags = merge({
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }, var.tags)
}

# ──────────────────────────────────────────────────────────────────────────────
# OpenAI API Key (PETPLAT-33)
# Stored as plaintext (the value itself is the key, no JSON wrapper needed).
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_secretsmanager_secret" "openai_api_key" {
  name        = "${var.project}/${var.environment}/openai-api-key"
  description = "OpenAI API key for genai-service in ${var.environment}"

  tags = merge(local.tags, {
    Name = "${var.project}-${var.environment}-openai-api-key"
  })
}

resource "aws_secretsmanager_secret_version" "openai_api_key" {
  secret_id     = aws_secretsmanager_secret.openai_api_key.id
  secret_string = var.openai_api_key
}

# ──────────────────────────────────────────────────────────────────────────────
# Grafana Admin Credentials (CRIT-001 fix)
# Stored in Secrets Manager so the password never appears in committed YAML.
# ESO pulls it into a K8s Secret in the monitoring namespace via ExternalSecret CR.
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_secretsmanager_secret" "grafana_admin" {
  name        = "${var.project}/${var.environment}/grafana-admin"
  description = "Grafana admin credentials for ${var.environment} observability stack"

  tags = merge(local.tags, {
    Name = "${var.project}-${var.environment}-grafana-admin"
  })
}

resource "aws_secretsmanager_secret_version" "grafana_admin" {
  secret_id     = aws_secretsmanager_secret.grafana_admin.id
  secret_string = jsonencode({
    username = "admin"
    password = var.grafana_admin_password
  })
}

# ──────────────────────────────────────────────────────────────────────────────
# ESO IRSA Role (PETPLAT-37)
# Grants External Secrets Operator permission to read from Secrets Manager.
# Trust policy scoped to the ESO service account in the external-secrets namespace.
# ──────────────────────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "eso_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:external-secrets:external-secrets-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "eso_permissions" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${var.project}/*"
    ]
  }
}

resource "aws_iam_policy" "eso" {
  name        = "${var.project}-${var.environment}-eso-policy"
  description = "Allows ESO to read petclinic secrets from Secrets Manager in ${var.environment}"
  policy      = data.aws_iam_policy_document.eso_permissions.json

  tags = local.tags
}

resource "aws_iam_role" "eso" {
  name               = "${var.project}-${var.environment}-eso-role"
  assume_role_policy = data.aws_iam_policy_document.eso_assume_role.json
  description        = "IRSA role for External Secrets Operator in ${var.environment}"

  tags = merge(local.tags, {
    Name = "${var.project}-${var.environment}-eso-role"
  })
}

resource "aws_iam_role_policy_attachment" "eso" {
  role       = aws_iam_role.eso.name
  policy_arn = aws_iam_policy.eso.arn
}
