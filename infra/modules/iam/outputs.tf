output "alb_controller_role_arn" {
  description = "IAM role ARN for the ALB Ingress Controller — annotated onto its service account"
  value       = aws_iam_role.alb_controller.arn
}

output "eso_role_arn" {
  description = "IAM role ARN for the External Secrets Operator — annotated onto its service account"
  value       = aws_iam_role.eso.arn
}

output "keda_role_arn" {
  description = "IAM role ARN for KEDA — annotated onto the keda-operator service account"
  value       = aws_iam_role.keda.arn
}

output "worker_role_arn" {
  description = "IAM role ARN for PDF workers — annotated onto the worker service account"
  value       = aws_iam_role.worker.arn
}
