data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support = true  
  tags = {
    Name = "${var.cluster}/vpc"
  }
}

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)
  vpc_id = aws_vpc.main.id
  cidr_block = var.public_subnet_cidrs[count.index]
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.cluster}/public-subnet-${data.aws_availability_zones.available.names[count.index]}"
    "kubernetes.io/cluster/${var.cluster}" = "owned"
    "kubernetes.io/role/elb"                    = "true"
  }
}

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)
  vpc_id = aws_vpc.main.id
  cidr_block = var.private_subnet_cidrs[count.index]
  map_public_ip_on_launch = false
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  tags = {
    Name                                        = "${var.cluster}-private-${count.index}"
    "kubernetes.io/cluster/${var.cluster}" = "owned"
    "kubernetes.io/role/internal-elb"           = "true"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.cluster}/igw"
  }
}

resource "aws_eip" "nat_eip" {
  domain = "vpc"
  tags = {
    Name = "${var.cluster}/nat_eip"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${var.cluster}/nat_gw"
  }
  depends_on = [aws_eip.nat_eip]
}

resource "aws_route_table" "custom" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "${var.cluster}/public_rt"
  }
}

resource "aws_route_table_association" "custom" {
    count = length(var.public_subnet_cidrs)
    subnet_id = aws_subnet.public[count.index].id
    route_table_id = aws_route_table.custom.id
}

resource "aws_route_table" "main" {
    vpc_id = aws_vpc.main.id

    route {
      cidr_block = "0.0.0.0/0"
      gateway_id = aws_nat_gateway.nat.id
    }
    tags ={
      Name = "${var.cluster}/private_rt"
    }
}

resource "aws_route_table_association" "main1" {
  count = length(var.private_subnet_cidrs)
  subnet_id = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.main.id
}

#IAM Role for EKS Cluster
resource "aws_iam_role" "eks_cluster_role" {
  name = "eksClusterRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "eks.amazonaws.com"
      },
      Action = [
          "sts:AssumeRole",
          "sts:TagSession"
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "EKSClusterPolicy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "EKSVPCResourceController" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}
  
#IAM Role for Worker Nodes (Node Group Role)
resource "aws_iam_role" "eks_node_role" {
  name = "eksNodeGroupRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}


resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "ec2_container_registry_readonly" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_eks_cluster" "eks_cluster" {
  name = var.cluster
  role_arn = aws_iam_role.eks_cluster_role.arn

  version  = "1.31"

  vpc_config {
    subnet_ids = concat(
      aws_subnet.public[*].id,
      aws_subnet.private[*].id
    )
    security_group_ids = [aws_security_group.eks_cluster_sg.id]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  # Ensure that IAM Role permissions are created before and deleted
  # after EKS Cluster handling. Otherwise, EKS will not be able to
  # properly delete EKS managed EC2 infrastructure such as Security Groups.
  depends_on = [
    aws_iam_role_policy_attachment.EKSClusterPolicy,
    aws_security_group.eks_cluster_sg
  ]
  tags = {
    Name = "${var.cluster}/eks-cluster"
  }
}

resource "aws_security_group" "eks_cluster_sg" {
  name        = "eks-cluster-sg"
  description = "Security group for EKS control plane communication"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow access to Kubernetes API server"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster}/eks_cluster_sg"
  }
}

resource "aws_eks_node_group" "node_group" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = "${var.cluster}-node-group"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = aws_subnet.private[*].id

  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 1
  }

  ami_type       = "AL2_x86_64"  # Amazon Linux 2
  instance_types = ["t3.medium"]
  disk_size      = 20

  tags = {
    "Name" = "${var.cluster}/node_group"
    "kubernetes.io/cluster/${aws_eks_cluster.eks_cluster.name}" = "owned"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.ec2_container_registry_readonly
    ]
}

/*
resource "aws_security_group" "eks_nodes_sg" {
  name        = "eks-nodes-sg"
  description = "Security group for EKS worker nodes"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow nodes to communicate with the cluster API Server"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    security_groups = [aws_security_group.eks_cluster_sg.id]  # From Cluster SG
  }

  ingress {
    description = "Allow worker nodes to communicate with each other (pod-to-pod networking)"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true  # Allow node-to-node full communication
  }

  ingress {
    description = "Allow worker nodes to communicate with each other (pod-to-pod networking - UDP)"
    from_port   = 0
    to_port     = 65535
    protocol    = "udp"
    self        = true
  }

  ingress {
    description = "Allow ICMP (Ping between nodes)"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    self        = true
  }

  egress {
    description = "Allow all outbound traffic (for internet access)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster}/eks_nodes_sg"
  }
}
*/

resource "kubernetes_namespace" "ns" {
  metadata {
    name = "glps-ns"
  }
  depends_on = [
    aws_eks_cluster.eks_cluster,
    aws_eks_node_group.node_group
    ]
}

resource "kubernetes_deployment" "webapp" {
  metadata {
    namespace = kubernetes_namespace.ns.metadata[0].name
    name = "glps-webapp-deployment"
    labels = {
      "app" = "amazon"
    }
  }
  spec {
    replicas = 2
    selector {
      match_labels = {
        "app" = "amazon"
      }
    }
    template {
      metadata {
        labels = {
          "app" = "amazon"
        }
      }
      spec {
        container {
          name  = "glps-webapp-container"
          image = var.web_image
          image_pull_policy = "Always"
          port {
            container_port = 80
          }
          resources {
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
            requests = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "webapp" {
  metadata {
    namespace = kubernetes_namespace.ns.metadata[0].name
    name = "glps-webapp-service"
  }
  spec {
    selector = {
      "app" = "amazon"
    }
    port {
      name        = "http"
      protocol    = "TCP"
      port        = 80
      target_port = 80
    }
    type = "LoadBalancer"
  }
}

/*
resource "kubernetes_ingress_v1" "webapp1" {
  metadata {
    namespace = kubernetes_namespace.ns.metadata[0].name
    name = "glps-webapp-ingress"
    annotations = {
      "kubernetes.io/ingress.class"                     = "alb"
      "alb.ingress.kubernetes.io/scheme"                = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"           = "ip"
      "alb.ingress.kubernetes.io/group.name"            = "shared-lb"
    }
  }

  spec {
    rule {
      http {
        path {
          path     = "/amazon"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.webapp.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}
*/
