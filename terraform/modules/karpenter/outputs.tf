output "karpenter_role_arn" {
  description = "IRSA role ARN for the Karpenter controller — annotate the karpenter ServiceAccount with this"
  value       = aws_iam_role.karpenter.arn
}

output "karpenter_queue_name" {
  description = "SQS interruption queue name — passed to Karpenter Helm values as settings.interruptionQueue"
  value       = aws_sqs_queue.karpenter_interruption.name
}

output "karpenter_instance_profile_name" {
  description = "Instance profile name for Karpenter-launched nodes — referenced in EC2NodeClass CRD spec.instanceProfile"
  value       = aws_iam_instance_profile.karpenter_node.name
}
