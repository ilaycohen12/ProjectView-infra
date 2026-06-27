output "signed_queue_url" {
  description = "Signed queue URL — used by the signed worker to receive and delete messages"
  value       = aws_sqs_queue.signed.url
}

output "signed_queue_arn" {
  description = "Signed queue ARN — used by IAM to write permission policies"
  value       = aws_sqs_queue.signed.arn
}

output "free_queue_url" {
  description = "Free queue URL — used by the free worker to receive and delete messages"
  value       = aws_sqs_queue.free.url
}

output "free_queue_arn" {
  description = "Free queue ARN — used by IAM to write permission policies"
  value       = aws_sqs_queue.free.arn
}
