data "aws_caller_identity" "current" {}

# GitHub Actions OIDC provider — one per AWS account, not per environment.
# Allows GitHub Actions to exchange a short-lived GitHub token for AWS credentials
# without storing any long-lived access keys anywhere.
resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  # sts.amazonaws.com is the required audience for GitHub OIDC federation with AWS
  client_id_list = ["sts.amazonaws.com"]

  # SHA1 thumbprint of GitHub's OIDC CA — AWS uses this to verify the token issuer
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = merge(var.tags, {
    Name        = "github-actions-oidc"
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

resource "aws_iam_role" "github_actions" {
  name        = var.role_name
  description = "Assumed by GitHub Actions in ${var.github_repo} to push images to ECR"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            # Audience must be sts.amazonaws.com (set by aws-actions/configure-aws-credentials)
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            # Restrict to the app repo main branch only — not the platform repo, not a wildcard
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:ref:refs/heads/main"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name        = var.role_name
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

resource "aws_iam_policy" "ecr_push" {
  name        = "${var.role_name}-ecr-push"
  description = "ECR push permissions for the petclinic-${var.environment} repositories — CI pipeline only"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # GetAuthorizationToken is account-level — cannot be scoped to a specific repository
        Sid      = "ECRAuthToken"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        # All image push actions scoped to petclinic-{env} repositories only
        Sid    = "ECRPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:BatchGetImage",
        ]
        Resource = "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/petclinic-${var.environment}/*"
      }
    ]
  })

  tags = merge(var.tags, {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

resource "aws_iam_role_policy_attachment" "ecr_push" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.ecr_push.arn
}
