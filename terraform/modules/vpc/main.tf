locals {
  name_prefix = "${var.project}-${var.environment}"
}

# ── VPC ───────────────────────────────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

# ── Internet Gateway ──────────────────────────────────────────────────────────

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-igw"
  })
}

# ── Public Subnets ────────────────────────────────────────────────────────────

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name                                         = "${local.name_prefix}-public-${count.index + 1}"
    "kubernetes.io/cluster/${local.name_prefix}" = "shared"
    "kubernetes.io/role/elb"                     = "1"
  })
}

# ── Route Table ───────────────────────────────────────────────────────────────

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ── Security Groups ───────────────────────────────────────────────────────────
# All rules are managed via aws_security_group_rule resources (not inline blocks)
# to avoid circular dependencies between security groups that reference each other.

resource "aws_security_group" "eks_cluster" {
  name        = "${local.name_prefix}-cluster-sg"
  description = "EKS cluster control plane - allows node-to-API-server communication"
  vpc_id      = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-cluster-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "eks_node" {
  name        = "${local.name_prefix}-node-sg"
  description = "EKS worker nodes - inter-node, control-plane, and ALB NodePort access"
  vpc_id      = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-node-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "RDS MySQL - allows port 3306 from EKS nodes only"
  vpc_id      = aws_vpc.main.id

  # No egress rules are defined here — this is intentional.
  # RDS does not initiate outbound connections in this architecture.
  # MySQL connections are always initiated inbound from EKS nodes on port 3306.
  # The absence of egress rules results in deny-all outbound by default for this SG.

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-rds-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "ALB - HTTP/HTTPS ingress from internet, egress to EKS NodePort range"
  vpc_id      = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-alb-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ── EKS Cluster SG Rules ──────────────────────────────────────────────────────

resource "aws_security_group_rule" "cluster_ingress_https_from_nodes" {
  type                     = "ingress"
  description              = "API Server access from worker nodes"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_node.id
  security_group_id        = aws_security_group.eks_cluster.id
}

resource "aws_security_group_rule" "cluster_egress_all" {
  type              = "egress"
  description       = "All outbound traffic"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.eks_cluster.id
}

# ── EKS Node SG Rules ─────────────────────────────────────────────────────────

# The broad "all from cluster" rule is intentional per the technical spec (Security Groups section).
# EKS managed node groups require unrestricted cluster-to-node access for control plane operations.
# The kubelet rule below is explicitly kept for documentation clarity even though it is a subset.
resource "aws_security_group_rule" "node_ingress_all_from_cluster" {
  type                     = "ingress"
  description              = "All traffic from cluster control plane"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.eks_cluster.id
  security_group_id        = aws_security_group.eks_node.id
}

resource "aws_security_group_rule" "node_ingress_self" {
  type              = "ingress"
  description       = "Inter-node communication"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  self              = true
  security_group_id = aws_security_group.eks_node.id
}

resource "aws_security_group_rule" "node_ingress_kubelet_from_cluster" {
  type                     = "ingress"
  description              = "Kubelet API from control plane"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_cluster.id
  security_group_id        = aws_security_group.eks_node.id
}

resource "aws_security_group_rule" "node_ingress_nodeport_from_alb" {
  type                     = "ingress"
  description              = "NodePort services from ALB"
  from_port                = 30000
  to_port                  = 32767
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.eks_node.id
}

resource "aws_security_group_rule" "node_ingress_pod_from_alb" {
  type                     = "ingress"
  description              = "Pod traffic from ALB (target-type: ip direct to pod port)"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.eks_node.id
}

resource "aws_security_group_rule" "node_egress_all" {
  type              = "egress"
  description       = "All outbound traffic"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.eks_node.id
}

# ── RDS SG Rules ──────────────────────────────────────────────────────────────

resource "aws_security_group_rule" "rds_ingress_mysql_from_nodes" {
  type                     = "ingress"
  description              = "MySQL from EKS nodes only - never 0.0.0.0/0"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_node.id
  security_group_id        = aws_security_group.rds.id
}

# ── ALB SG Rules ──────────────────────────────────────────────────────────────

resource "aws_security_group_rule" "alb_ingress_http" {
  type              = "ingress"
  description       = "HTTP from internet"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
}

resource "aws_security_group_rule" "alb_ingress_https" {
  type              = "ingress"
  description       = "HTTPS from internet"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
}

resource "aws_security_group_rule" "alb_egress_nodeport" {
  type                     = "egress"
  description              = "To EKS nodes - NodePort range (target group traffic)"
  from_port                = 30000
  to_port                  = 32767
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_node.id
  security_group_id        = aws_security_group.alb.id
}

resource "aws_security_group_rule" "alb_egress_health" {
  type                     = "egress"
  description              = "To EKS nodes - health check port 8080"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_node.id
  security_group_id        = aws_security_group.alb.id
}
