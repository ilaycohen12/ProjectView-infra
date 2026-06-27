output "bucket_name" {
  description = "Bucket name — used by workers to upload PDFs and by web server to generate presigned URLs"
  value       = aws_s3_bucket.pdfs.bucket
}

output "bucket_arn" {
  description = "Bucket ARN — used by IAM to write permission policies for workers"
  value       = aws_s3_bucket.pdfs.arn
}
