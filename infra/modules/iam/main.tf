# ── Data source: get the AWS account ID at runtime ──────────────────────────
data "aws_caller_identity" "current" {}

# ── Local: strip the ARN prefix to get the plain OIDC URL ───────────────────
# e.g. arn:aws:iam::123:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/XXX
#   →  oidc.eks.us-east-1.amazonaws.com/id/XXX
locals {
  oidc_url = replace(
    var.oidc_provider_arn,
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/",
    ""
  )
}

# ── ALB Ingress Controller ───────────────────────────────────────────────────

# Role — trusts only the alb-controller service account in kube-system namespace
resource "aws_iam_role" "alb_controller" {
  name = "${var.cluster_name}-alb-controller"  # e.g. "projectview-dev-alb-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }  # trusts this cluster's OIDC provider
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_url}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"  # locked to this exact service account
          "${local.oidc_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = { Environment = var.env_name, ManagedBy = "terragrunt" }
}

# Policy — permissions the ALB controller needs to manage AWS load balancers
resource "aws_iam_policy" "alb_controller" {
  name = "${var.cluster_name}-alb-controller"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:Describe*"]                          # read VPCs, subnets, security groups
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:*"]                 # create and manage ALBs and target groups
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["iam:CreateServiceLinkedRole"]            # needed to create the ELB service-linked role on first run
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["acm:DescribeCertificate", "acm:ListCertificates"]  # needed for HTTPS listeners
        Resource = "*"
      }
    ]
  })
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "alb_controller" {
  policy_arn = aws_iam_policy.alb_controller.arn  # the policy above
  role       = aws_iam_role.alb_controller.name   # the role above
}

# ── External Secrets Operator ────────────────────────────────────────────────

# Role — trusts only the external-secrets service account in external-secrets namespace
resource "aws_iam_role" "eso" {
  name = "${var.cluster_name}-eso"  # e.g. "projectview-dev-eso"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }  # trusts this cluster's OIDC provider
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_url}:sub" = "system:serviceaccount:external-secrets:external-secrets"  # locked to ESO service account
          "${local.oidc_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = { Environment = var.env_name, ManagedBy = "terragrunt" }
}

# Policy — ESO only needs to read secrets, nothing else
resource "aws_iam_policy" "eso" {
  name = "${var.cluster_name}-eso"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",   # read the secret value
        "secretsmanager:DescribeSecret"    # read secret metadata (name, ARN, tags)
      ]
      Resource = "*"  # all secrets in this account — can be scoped to specific ARNs later
    }]
  })
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "eso" {
  policy_arn = aws_iam_policy.eso.arn  # the policy above
  role       = aws_iam_role.eso.name   # the role above
}

# ── KEDA ─────────────────────────────────────────────────────────────────────
# KEDA needs to read queue depth to decide how many worker pods to scale to

resource "aws_iam_role" "keda" {
  name = "${var.cluster_name}-keda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_url}:sub" = "system:serviceaccount:keda:keda-operator" # locked to KEDA operator service account
          "${local.oidc_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = { Environment = var.env_name, ManagedBy = "terragrunt" }
}

resource "aws_iam_policy" "keda" {
  name = "${var.cluster_name}-keda"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:GetQueueAttributes"] # read queue depth — the only thing KEDA needs
      Resource = [var.signed_queue_arn]      # only the signed queue — KEDA only watches this one
    }]
  })
}

resource "aws_iam_role_policy_attachment" "keda" {
  policy_arn = aws_iam_policy.keda.arn
  role       = aws_iam_role.keda.name
}

# ── PDF Worker ────────────────────────────────────────────────────────────────
# Both signed and free workers share one IAM role — same permissions, different queue URLs via env vars

resource "aws_iam_role" "worker" {
  name = "${var.cluster_name}-worker"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_url}:sub" = "system:serviceaccount:default:worker" # locked to worker service account
          "${local.oidc_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = { Environment = var.env_name, ManagedBy = "terragrunt" }
}

resource "aws_iam_policy" "worker" {
  name = "${var.cluster_name}-worker"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",    # pick up a message from the queue
          "sqs:DeleteMessage",     # delete it after processing
          "sqs:GetQueueAttributes" # read queue metadata
        ]
        Resource = [var.signed_queue_arn, var.free_queue_arn] # both queues
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject", # upload the generated PDF
          "s3:GetObject"  # needed to generate presigned download URLs
        ]
        Resource = "${var.bucket_arn}/*" # all objects inside the PDF bucket
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "worker" {
  policy_arn = aws_iam_policy.worker.arn
  role       = aws_iam_role.worker.name
}
