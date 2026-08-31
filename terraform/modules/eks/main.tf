data "aws_partition" "current" {}

# Restricts the public API endpoint to the caller's current IP (plus any
# explicitly allow-listed CIDRs) instead of leaving it open to 0.0.0.0/0.
# Keeps the "no VPN/bastion needed to kubectl from a laptop" convenience of a
# public endpoint without actually leaving it open to the whole internet.
data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

locals {
  endpoint_public_access_cidrs = concat(
    ["${chomp(data.http.my_ip.response_body)}/32"],
    var.additional_endpoint_public_access_cidrs,
  )

  # Normally "${cluster_name}-cluster" (multi-cluster-safe within one AWS
  # account). Override only when an external constraint demands one exact
  # literal name — see var.cluster_iam_role_name's description.
  cluster_iam_role_name = coalesce(var.cluster_iam_role_name, "${var.cluster_name}-cluster")
}

# ---------------------------------------------------------------------------
# KMS key for EKS secrets envelope encryption — encrypts Kubernetes Secrets
# at rest in etcd with a customer-managed key, not just AWS's default one.
# ---------------------------------------------------------------------------

resource "aws_kms_key" "eks_secrets" {
  description             = "EKS secrets envelope encryption for ${var.cluster_name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  tags                    = var.tags
}

resource "aws_kms_alias" "eks_secrets" {
  name          = "alias/${var.cluster_name}-eks-secrets"
  target_key_id = aws_kms_key.eks_secrets.key_id
}

# ---------------------------------------------------------------------------
# Cluster IAM role
# ---------------------------------------------------------------------------

resource "aws_iam_role" "cluster" {
  name = local.cluster_iam_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ---------------------------------------------------------------------------
# Cluster
# ---------------------------------------------------------------------------

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.cluster_version

  # Accepted risk, with a compensating control: public_access_cidrs below
  # restricts this to the caller's own IP (auto-detected) plus any
  # explicitly allow-listed CIDRs, not 0.0.0.0/0. Disabling public access
  # entirely (the alternative this rule wants) would require a VPN or
  # bastion host to reach a personal dev cluster from a laptop — the right
  # call for production, not for this project. See
  # var.endpoint_public_access's description for the full tradeoff.
  #tfsec:ignore:aws-eks-no-public-cluster-access
  vpc_config {
    subnet_ids              = concat(var.private_subnet_ids, var.public_subnet_ids)
    endpoint_public_access  = var.endpoint_public_access
    endpoint_private_access = true
    public_access_cidrs     = var.endpoint_public_access ? local.endpoint_public_access_cidrs : null
  }

  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.eks_secrets.arn
    }
  }

  access_config {
    authentication_mode = "API" # modern IAM-based access instead of the legacy aws-auth ConfigMap
  }

  tags = var.tags

  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
}

# ---------------------------------------------------------------------------
# OIDC provider — required for IRSA (pods assuming IAM roles directly), used
# by the AWS Load Balancer Controller and External Secrets Operator later
# (Phase 7-9). No cost on its own; this is what makes that possible.
# ---------------------------------------------------------------------------

data "tls_certificate" "eks" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Node IAM role
# ---------------------------------------------------------------------------

resource "aws_iam_role" "node" {
  name = "${var.cluster_name}-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_readonly" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ---------------------------------------------------------------------------
# Self-managed worker nodes (launch template + Auto Scaling Group), NOT a
# managed node group (aws_eks_node_group).
#
# WHY: this project's KodeKloud sandbox lab account's IAM policy grants
# eks:CreateCluster and iam:PassRole to eks.amazonaws.com (for a role named
# exactly "eksClusterRole" — see var.cluster_iam_role_name), but does not
# grant eks:CreateNodegroup or eks:CreateFargateProfile at all — confirmed
# via `aws iam simulate-principal-policy` (a read-only permission check, no
# resources created) before writing any of this. It does grant
# ec2:RunInstances, autoscaling:CreateAutoScalingGroup, and iam:PassRole to
# ec2.amazonaws.com, which is exactly what a self-managed node group needs.
# This is a KodeKloud sandbox compatibility adaptation, not the production
# default — a real AWS account with standard permissions should prefer
# aws_eks_node_group (simpler: AWS handles AMI selection, bootstrap, and
# rolling updates for you). This module still stays reusable there: nothing
# here is KodeKloud-specific except var.cluster_iam_role_name's value,
# supplied by the caller, not hardcoded in this module.
#
# Worker nodes only ever go in private subnets — same as before.
# ---------------------------------------------------------------------------

resource "aws_iam_instance_profile" "node" {
  name = "${var.cluster_name}-node"
  role = aws_iam_role.node.name
  tags = var.tags
}

# Latest EKS-optimized Amazon Linux 2023 AMI matching the control plane's
# Kubernetes version, resolved via AWS's published SSM parameter rather than
# a hardcoded AMI ID (which would silently go stale and eventually mismatch
# the control plane version).
data "aws_ssm_parameter" "eks_ami" {
  name = "/aws/service/eks/optimized-ami/${var.cluster_version}/amazon-linux-2023/x86_64/standard/recommended/image_id"
}

# AL2023's bootstrap mechanism ("nodeadm") takes a YAML NodeConfig via
# user-data, not the older AL2 /etc/eks/bootstrap.sh shell-script format.
# This is what actually joins each instance to the cluster on first boot.
locals {
  node_userdata = base64encode(<<-EOT
    ---
    apiVersion: node.eks.aws/v1alpha1
    kind: NodeConfig
    spec:
      cluster:
        name: ${aws_eks_cluster.this.name}
        apiServerEndpoint: ${aws_eks_cluster.this.endpoint}
        certificateAuthority: ${aws_eks_cluster.this.certificate_authority[0].data}
        cidr: ${aws_eks_cluster.this.kubernetes_network_config[0].service_ipv4_cidr}
  EOT
  )
}

resource "aws_launch_template" "node" {
  name_prefix   = "${var.cluster_name}-node-"
  image_id      = data.aws_ssm_parameter.eks_ami.value
  instance_type = var.node_instance_types[0]
  user_data     = local.node_userdata

  iam_instance_profile {
    name = aws_iam_instance_profile.node.name
  }

  # Reuses the cluster's own auto-created security group rather than
  # hand-writing node<->control-plane rules (ports 443/10250 + ephemeral
  # range) — this SG already has everything a managed node group's nodes
  # would get automatically; self-managed nodes just have to attach it
  # explicitly. This is AWS's own documented pattern for self-managed nodes.
  vpc_security_group_ids = [aws_eks_cluster.this.vpc_config[0].cluster_security_group_id]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 2          # nodeadm needs metadata access from inside containers
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name = "${var.cluster_name}-node"
    })
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "node" {
  name                      = "${var.cluster_name}-node"
  vpc_zone_identifier       = var.private_subnet_ids
  desired_capacity          = var.node_desired_size
  min_size                  = var.node_min_size
  max_size                  = var.node_max_size
  health_check_type         = "EC2"
  health_check_grace_period = 300 # time for nodeadm bootstrap + kubelet registration before a failed check triggers replacement

  launch_template {
    id      = aws_launch_template.node.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.cluster_name}-node"
    propagate_at_launch = true
  }

  # Required so AWS's own tooling (and, later, Cluster Autoscaler) recognizes
  # these instances as belonging to this cluster — the same tag a managed
  # node group would carry automatically.
  tag {
    key                 = "kubernetes.io/cluster/${var.cluster_name}"
    value               = "owned"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr_readonly,
    aws_eks_access_entry.node,
  ]
}

# ---------------------------------------------------------------------------
# Cluster authentication for the worker role — access entries, not the
# aws-auth ConfigMap. This cluster's access_config.authentication_mode is
# "API" (pure IAM-based access, set above), which means the aws-auth
# ConfigMap is not consulted for authentication at all; only
# API_AND_CONFIG_MAP or the legacy CONFIG_MAP mode would read it. A managed
# node group gets an access entry created for it automatically; a
# self-managed node group has to create one explicitly — that's this
# resource. type = "EC2_LINUX" is the access-entry type AWS specifically
# built for self-managed EC2 Linux worker nodes.
# ---------------------------------------------------------------------------

resource "aws_eks_access_entry" "node" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_iam_role.node.arn
  type          = "EC2_LINUX"

  tags = var.tags
}
