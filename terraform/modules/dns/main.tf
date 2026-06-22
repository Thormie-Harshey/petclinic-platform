locals {
  common_tags = merge(var.tags, {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# ─── Route 53 Hosted Zone ────────────────────────────────────────────────────

resource "aws_route53_zone" "this" {
  name = var.domain_name

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-hosted-zone"
  })
}

# ─── ACM Wildcard Certificate ─────────────────────────────────────────────────

resource "aws_acm_certificate" "this" {
  domain_name               = "*.${var.domain_name}"
  subject_alternative_names = [var.domain_name]
  validation_method         = "DNS"

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-cert"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# DNS validation CNAME records — written into the Route 53 zone so ACM can verify ownership.
# ACM polls these records until the certificate is issued.
# NOTE: These records only resolve once you update GoDaddy's nameservers to Route 53 (see outputs.name_servers).
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.this.zone_id
}

# Blocks until ACM confirms the certificate is issued (up to 30 min).
# Update GoDaddy nameservers to Route 53 (outputs.name_servers) immediately after
# the hosted zone is created so DNS propagates before the timeout.
resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]

  timeouts {
    create = "30m"
  }
}

# ─── AWS Load Balancer Controller — IAM (PETPLAT-29) ────────────────────────

resource "aws_iam_policy" "lb_controller" {
  name        = "${var.project}-${var.environment}-lb-controller-policy"
  description = "IAM policy for the AWS Load Balancer Controller running in EKS"
  policy      = file("${path.module}/files/lb-controller-iam-policy.json")

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-lb-controller-policy"
  })
}

data "aws_iam_policy_document" "lb_controller_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lb_controller" {
  name               = "${var.project}-${var.environment}-lb-controller-role"
  assume_role_policy = data.aws_iam_policy_document.lb_controller_assume.json
  description        = "IRSA role for the AWS Load Balancer Controller in ${var.environment}"

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-lb-controller-role"
  })
}

resource "aws_iam_role_policy_attachment" "lb_controller" {
  policy_arn = aws_iam_policy.lb_controller.arn
  role       = aws_iam_role.lb_controller.name
}

# ─── Route 53 A Record → ALB (PETPLAT-31) ────────────────────────────────────
# This record is created in a SECOND terraform apply, after:
#   1. install-lb-controller.sh has been run
#   2. k8s/base/ingress/ingress.yaml has been applied to the cluster
#   3. The ALB is provisioned (~2-3 min) and its DNS name is known
#
# To get the ALB DNS name:
#   kubectl get ingress -n petclinic-{env} \
#     -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'
#
# Then set alb_dns_name in terraform.tfvars and run terraform apply again.

resource "aws_route53_record" "app" {
  count = var.alb_dns_name != null ? 1 : 0

  zone_id = aws_route53_zone.this.zone_id
  name    = "${var.project}-${var.environment}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}
