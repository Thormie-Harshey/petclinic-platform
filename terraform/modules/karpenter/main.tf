locals {
  name_prefix = "${var.project}-${var.environment}"

  # Extract node role name from ARN (arn:aws:iam::account:role/name → name)
  node_role_name = split("/", var.node_role_arn)[1]

  common_tags = merge(var.tags, {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# -------------------------------------------------------------------
# IAM Role for Karpenter controller (IRSA)
# -------------------------------------------------------------------
# This role is assumed by the Karpenter pod running in kube-system.
# The OIDC trust policy ties it to exactly one ServiceAccount
# (karpenter in kube-system) so no other pod can use it.

resource "aws_iam_role" "karpenter" {
  name = "${local.name_prefix}-karpenter-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider_url}:sub" = "system:serviceaccount:kube-system:karpenter"
          "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = local.common_tags
}

# -------------------------------------------------------------------
# IAM Policy for Karpenter controller
# -------------------------------------------------------------------
# ec2:*        — provision, tag, and terminate EC2 instances and launch templates
# iam:PassRole — hand the node IAM role to new EC2 instances (scoped to node role only)
# ssm:GetParam — read EC2 AMI IDs from SSM Parameter Store (Karpenter uses this for al2023)
# pricing:*    — read EC2 spot pricing to pick cheapest available instance type
# sqs:*        — read/delete spot interruption messages from the queue
# eks:Describe — read cluster config (VPC, CIDR) to configure new nodes correctly

resource "aws_iam_policy" "karpenter" {
  name        = "${local.name_prefix}-karpenter-policy"
  description = "Karpenter controller permissions for node provisioning"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "KarpenterEC2"
        Effect = "Allow"
        Action = [
          "ec2:CreateFleet",
          "ec2:CreateLaunchTemplate",
          "ec2:CreateTags",
          "ec2:DeleteLaunchTemplate",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeSubnets",
          "ec2:RunInstances",
          "ec2:TerminateInstances",
        ]
        Resource = "*"
      },
      {
        Sid    = "KarpenterPassRole"
        Effect = "Allow"
        Action = ["iam:PassRole"]
        # Scoped to the node role only — prevents privilege escalation
        Resource = var.node_role_arn
      },
      {
        Sid      = "KarpenterSSM"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = "arn:aws:ssm:*:*:parameter/aws/service/eks/optimized-ami/*"
      },
      {
        Sid      = "KarpenterPricing"
        Effect   = "Allow"
        Action   = ["pricing:GetProducts"]
        Resource = "*"
      },
      {
        Sid    = "KarpenterSQS"
        Effect = "Allow"
        Action = [
          "sqs:GetQueueUrl",
          "sqs:GetQueueAttributes",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:ChangeMessageVisibility",
        ]
        Resource = aws_sqs_queue.karpenter_interruption.arn
      },
      {
        Sid      = "KarpenterEKS"
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = "arn:aws:eks:*:*:cluster/${var.cluster_name}"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "karpenter" {
  role       = aws_iam_role.karpenter.name
  policy_arn = aws_iam_policy.karpenter.arn
}

# -------------------------------------------------------------------
# IAM Instance Profile for Karpenter-launched nodes
# -------------------------------------------------------------------
# When Karpenter boots a new EC2 instance it attaches this profile.
# The profile carries the existing node IAM role so the new node can
# join the cluster and pull images from ECR.
# Name MUST be petclinic-{env}-karpenter-node-profile — this exact
# name is referenced in the EC2NodeClass CRD.

resource "aws_iam_instance_profile" "karpenter_node" {
  name = "${local.name_prefix}-karpenter-node-profile"
  role = local.node_role_name

  tags = local.common_tags
}

# -------------------------------------------------------------------
# SQS Interruption Queue
# -------------------------------------------------------------------
# AWS sends spot interruption warnings here (via EventBridge rules below).
# Karpenter polls this queue and gracefully drains pods off the node
# before AWS reclaims it.
# visibility_timeout = 1200s (20 min) — gives Karpenter enough time to
# process the message and drain the node before SQS re-delivers it.

resource "aws_sqs_queue" "karpenter_interruption" {
  name                       = "${local.name_prefix}-karpenter-interruption"
  visibility_timeout_seconds = 1200

  tags = local.common_tags
}

# SQS Resource Policy — allows EventBridge to send messages to this queue.
# Without this policy, EventBridge rules deliver to the queue URL but SQS
# rejects the request with AccessDenied and the warning is silently dropped.

resource "aws_sqs_queue_policy" "karpenter_interruption" {
  queue_url = aws_sqs_queue.karpenter_interruption.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.karpenter_interruption.arn
    }]
  })
}

# -------------------------------------------------------------------
# EventBridge Rules → SQS (4 events Karpenter needs to handle)
# -------------------------------------------------------------------

# Rule 1: Spot Instance Interruption Warning
# Fired ~2 minutes before AWS reclaims a spot instance.
resource "aws_cloudwatch_event_rule" "spot_interruption" {
  name        = "${local.name_prefix}-karpenter-spot-interruption"
  description = "Karpenter: route EC2 spot interruption warnings to SQS"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Spot Instance Interruption Warning"]
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "spot_interruption" {
  rule = aws_cloudwatch_event_rule.spot_interruption.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}

# Rule 2: Rebalance Recommendation
# AWS suggests moving workloads off a spot instance before it gets interrupted.
resource "aws_cloudwatch_event_rule" "rebalance" {
  name        = "${local.name_prefix}-karpenter-rebalance"
  description = "Karpenter: route EC2 rebalance recommendations to SQS"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance Rebalance Recommendation"]
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "rebalance" {
  rule = aws_cloudwatch_event_rule.rebalance.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}

# Rule 3: Instance State Change
# Fires when an instance transitions states (pending → running → shutting-down → terminated).
# Karpenter uses this to detect nodes that terminated unexpectedly.
resource "aws_cloudwatch_event_rule" "instance_state_change" {
  name        = "${local.name_prefix}-karpenter-instance-state"
  description = "Karpenter: route EC2 instance state-change notifications to SQS"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "instance_state_change" {
  rule = aws_cloudwatch_event_rule.instance_state_change.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}

# Rule 4: AWS Health Events (scheduled maintenance)
# Fires when AWS schedules maintenance that will affect an instance —
# gives Karpenter advance notice to migrate workloads.
resource "aws_cloudwatch_event_rule" "health_event" {
  name        = "${local.name_prefix}-karpenter-health-event"
  description = "Karpenter: route AWS Health scheduled change events to SQS"

  event_pattern = jsonencode({
    source      = ["aws.health"]
    detail-type = ["AWS Health Event"]
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "health_event" {
  rule = aws_cloudwatch_event_rule.health_event.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}
