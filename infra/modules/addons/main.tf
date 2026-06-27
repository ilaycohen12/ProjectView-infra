data "aws_region" "current" {}

# ── Kubernetes Provider ───────────────────────────────────────────────────────
# Helm provider v3 no longer accepts a kubernetes block — configure it separately
provider "kubernetes" {
  host                   = var.cluster_endpoint
  cluster_ca_certificate = base64decode(var.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
  }
}

# ── Helm Provider ─────────────────────────────────────────────────────────────
# In Helm provider v3, cluster auth is picked up from the kubernetes provider above
provider "helm" {}

# ── ALB Ingress Controller ────────────────────────────────────────────────────
# Watches for Ingress resources and creates real AWS ALBs from them
resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system" # kube-system already exists — no create_namespace needed
  version    = "1.7.1"

  set {
    name  = "clusterName"
    value = var.cluster_name # tells the controller which cluster it's managing
  }

  set {
    name  = "vpcId"
    value = var.vpc_id # tells the controller which VPC to create ALBs in
  }

  set {
    name  = "region"
    value = data.aws_region.current.name # us-east-1
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.alb_controller_role_arn # IRSA — gives the controller permission to create ALBs
  }
}

# ── External Secrets Operator ─────────────────────────────────────────────────
# Watches ExternalSecret resources and syncs values from Secrets Manager into K8s secrets
resource "helm_release" "eso" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  version          = "0.9.11"
  create_namespace = true

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.eso_role_arn # IRSA — gives ESO permission to read from Secrets Manager
  }
}

# ── ArgoCD ────────────────────────────────────────────────────────────────────
# GitOps CD tool — watches the gitops repo and deploys changes to the cluster
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  version          = "6.7.3"
  create_namespace = true

  set {
    name  = "server.service.type"
    value = "LoadBalancer" # creates an AWS load balancer so the ArgoCD UI is reachable from a browser
  }
}

# ── KEDA ──────────────────────────────────────────────────────────────────────
# Watches ScaledObject resources and scales Deployments based on SQS queue depth
resource "helm_release" "keda" {
  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  namespace        = "keda"
  version          = "2.13.1"
  create_namespace = true

  set {
    name  = "serviceAccount.operator.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.keda_role_arn # IRSA — gives KEDA permission to read SQS queue depth
  }
}
