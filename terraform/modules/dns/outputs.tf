output "zone_id" {
  description = "Route 53 hosted zone ID"
  value       = aws_route53_zone.this.zone_id
}

output "zone_name" {
  description = "Domain name of the hosted zone"
  value       = aws_route53_zone.this.name
}

output "name_servers" {
  description = "Route 53 NS records — copy these 4 values into GoDaddy's nameserver settings to delegate DNS to Route 53"
  value       = aws_route53_zone.this.name_servers
}

output "certificate_arn" {
  description = "ACM certificate ARN — paste this into k8s/base/ingress/ingress.yaml and the ALB Ingress annotation"
  value       = aws_acm_certificate_validation.this.certificate_arn
}

output "lb_controller_role_arn" {
  description = "IRSA role ARN for the AWS Load Balancer Controller — pass this to scripts/install-lb-controller.sh"
  value       = aws_iam_role.lb_controller.arn
}

output "app_url" {
  description = "Application URL (only populated after second apply sets alb_dns_name)"
  value       = var.alb_dns_name != null ? "https://${var.project}-${var.environment}.${var.domain_name}" : "Not yet configured — set alb_dns_name in terraform.tfvars after the ALB is provisioned"
}
