# EKS Module
# PETPLAT-12: cluster + cluster IAM role + OIDC provider
# PETPLAT-13: managed node group + node IAM role + launch template
# PETPLAT-14: kubectl access entries
# PETPLAT-84: managed add-ons (coredns, kube-proxy, vpc-cni, aws-ebs-csi-driver) + EBS CSI IRSA + VPC CNI IRSA

locals {
  cluster_name      = "${var.project}-${var.environment}"
  oidc_provider_url = replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ──────────────────────────────────────────────────────────────────────────────
# Cluster IAM Role (PETPLAT-12)
# ──────────────────────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${local.cluster_name}-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json

  tags = merge(var.tags, {
    Name = "${local.cluster_name}-cluster-role"
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ──────────────────────────────────────────────────────────────────────────────
# EKS Cluster (PETPLAT-12)
# Fix #1: all 5 log types enabled (was missing controllerManager + scheduler)
# Fix #2: private endpoint enabled so node-to-API traffic stays inside VPC
# Fix #3: public_access_cidrs restricts who can reach the API server
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = [var.cluster_sg_id]
    endpoint_public_access  = true
    endpoint_private_access = true
    public_access_cidrs     = var.allowed_public_cidrs
  }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = merge(var.tags, {
    Name = local.cluster_name
  })

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
  ]
}

# ──────────────────────────────────────────────────────────────────────────────
# OIDC Provider for IRSA (PETPLAT-12)
# Fix #4: second thumbprint added as resilience against AWS root CA rotation
# ──────────────────────────────────────────────────────────────────────────────

data "tls_certificate" "cluster_oidc" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = [
    data.tls_certificate.cluster_oidc.certificates[0].sha1_fingerprint,
    "9e99a48a9960b14926bb7f3b02e22da2b0ab7280",
  ]
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = merge(var.tags, {
    Name = "${local.cluster_name}-oidc"
  })
}

# ──────────────────────────────────────────────────────────────────────────────
# Node IAM Role (PETPLAT-13)
# Fix #5: AmazonEKS_CNI_Policy removed from node role — moved to IRSA below.
# Node role carries only the minimum required by the kubelet and EC2 join process.
# ──────────────────────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "node_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "node" {
  name               = "${local.cluster_name}-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json

  tags = merge(var.tags, {
    Name = "${local.cluster_name}-node-role"
  })
}

resource "aws_iam_role_policy_attachment" "node_worker_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ──────────────────────────────────────────────────────────────────────────────
# IRSA Role for VPC CNI (aws-node DaemonSet) (Fix #5)
# Scoped to kube-system:aws-node so only the CNI DaemonSet can call EC2 APIs.
# ──────────────────────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "vpc_cni_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.cluster.arn]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:kube-system:aws-node"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "vpc_cni" {
  name               = "${local.cluster_name}-vpc-cni-role"
  assume_role_policy = data.aws_iam_policy_document.vpc_cni_assume_role.json

  tags = merge(var.tags, {
    Name = "${local.cluster_name}-vpc-cni-role"
  })
}

resource "aws_iam_role_policy_attachment" "vpc_cni_policy" {
  role       = aws_iam_role.vpc_cni.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# ──────────────────────────────────────────────────────────────────────────────
# Node Launch Template (PETPLAT-13)
# Attaches the custom node SG, enforces IMDSv2 with hop-limit=2 (pods need 2
# hops to reach IMDS for IRSA), and configures the encrypted gp3 root volume.
# disk_size is set here (not on aws_eks_node_group) — they are mutually
# exclusive when a launch template is used.
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_launch_template" "node" {
  name_prefix = "${local.cluster_name}-node-"
  description = "Launch template for ${local.cluster_name} managed node group"

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.node_disk_size
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  vpc_security_group_ids = [var.node_sg_id]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = "${local.cluster_name}-node"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(var.tags, {
      Name = "${local.cluster_name}-node-volume"
    })
  }

  tags = merge(var.tags, {
    Name = "${local.cluster_name}-node-launch-template"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# Managed Node Group (PETPLAT-13)
# Fix #6: launch_template version pinned to "$Default" instead of latest_version.
# Using latest_version causes a rolling node replacement on every LT change
# (including tag-only updates). Nodes roll only when you explicitly update the
# default version or when scaling_config / AMI changes require it.
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.cluster_name}-nodes"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  instance_types = var.node_instance_types
  ami_type       = var.node_ami_type
  capacity_type  = "ON_DEMAND"

  launch_template {
    id      = aws_launch_template.node.id
    version = "$Default"
  }

  scaling_config {
    min_size     = var.node_min_size
    max_size     = var.node_max_size
    desired_size = var.node_desired_size
  }

  labels = {
    environment = var.environment
    managed-by  = "terraform"
  }

  tags = merge(var.tags, {
    Name = "${local.cluster_name}-nodes"
  })

  depends_on = [
    aws_iam_role_policy_attachment.node_worker_policy,
    aws_iam_role_policy_attachment.node_ecr_policy,
    aws_eks_addon.vpc_cni,
  ]
}

# ──────────────────────────────────────────────────────────────────────────────
# Cluster Access Entries (PETPLAT-14)
# Grants cluster admin to explicitly listed IAM principals.
# bootstrap_cluster_creator_admin_permissions = true ensures the deploying
# identity always retains access even if cluster_admin_arns is empty.
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_eks_access_entry" "admin" {
  for_each = toset(var.cluster_admin_arns)

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value
  type          = "STANDARD"

  tags = merge(var.tags, {
    Name = "${local.cluster_name}-admin-${basename(each.value)}"
  })
}

resource "aws_eks_access_policy_association" "admin" {
  for_each = toset(var.cluster_admin_arns)

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin]
}

# ──────────────────────────────────────────────────────────────────────────────
# EKS Add-on versions (PETPLAT-84)
# most_recent = true resolves the latest version compatible with the cluster's
# Kubernetes version at plan time. The resolved version is stored in state and
# does not change on subsequent applies unless you explicitly re-run plan+apply.
# ──────────────────────────────────────────────────────────────────────────────

data "aws_eks_addon_version" "coredns" {
  addon_name         = "coredns"
  kubernetes_version = aws_eks_cluster.main.version
  most_recent        = true
}

data "aws_eks_addon_version" "kube_proxy" {
  addon_name         = "kube-proxy"
  kubernetes_version = aws_eks_cluster.main.version
  most_recent        = true
}

data "aws_eks_addon_version" "vpc_cni" {
  addon_name         = "vpc-cni"
  kubernetes_version = aws_eks_cluster.main.version
  most_recent        = true
}

data "aws_eks_addon_version" "ebs_csi" {
  addon_name         = "aws-ebs-csi-driver"
  kubernetes_version = aws_eks_cluster.main.version
  most_recent        = true
}

# ──────────────────────────────────────────────────────────────────────────────
# EKS Managed Add-ons (PETPLAT-84)
# Fix #10: vpc-cni uses PRESERVE on update to protect custom configuration
# (e.g. ENABLE_PREFIX_DELEGATION, WARM_IP_TARGET) applied outside Terraform.
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "vpc-cni"
  addon_version               = data.aws_eks_addon_version.vpc_cni.version
  service_account_role_arn    = aws_iam_role.vpc_cni.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  tags = merge(var.tags, {
    Name = "${local.cluster_name}-vpc-cni"
  })

  # vpc-cni must be applied BEFORE the node group so the aws-node DaemonSet
  # has its IRSA annotation set when nodes first join. Without it, aws-node
  # crashes (no IAM credentials), nodes stay NotReady, and the managed node
  # group times out with CREATE_FAILED.
  depends_on = [
    aws_iam_role_policy_attachment.vpc_cni_policy,
  ]
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "coredns"
  addon_version               = data.aws_eks_addon_version.coredns.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(var.tags, {
    Name = "${local.cluster_name}-coredns"
  })

  depends_on = [aws_eks_node_group.main]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "kube-proxy"
  addon_version               = data.aws_eks_addon_version.kube_proxy.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(var.tags, {
    Name = "${local.cluster_name}-kube-proxy"
  })

  depends_on = [aws_eks_node_group.main]
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = data.aws_eks_addon_version.ebs_csi.version
  service_account_role_arn    = aws_iam_role.ebs_csi.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(var.tags, {
    Name = "${local.cluster_name}-ebs-csi-driver"
  })

  depends_on = [aws_eks_node_group.main]
}

# ──────────────────────────────────────────────────────────────────────────────
# IRSA Role for EBS CSI Driver (PETPLAT-84)
# Scoped to kube-system:ebs-csi-controller-sa.
# ──────────────────────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "ebs_csi_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.cluster.arn]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${local.cluster_name}-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role.json

  tags = merge(var.tags, {
    Name = "${local.cluster_name}-ebs-csi-role"
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi_policy" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
