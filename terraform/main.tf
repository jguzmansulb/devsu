provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "eks_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "eks-vpc"
  }
}

resource "aws_subnet" "eks_public_subnet" {
  vpc_id            = aws_vpc.eks_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = element(data.aws_availability_zones.available.names, 0)
  map_public_ip_on_launch = true

  tags = {
    Name = "eks-public-subnet"
  }
}

resource "aws_subnet" "eks_private_subnet" {
  vpc_id            = aws_vpc.eks_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = element(data.aws_availability_zones.available.names, 1)
  map_public_ip_on_launch = false

  tags = {
    Name = "eks-private-subnet"
  }
}

resource "aws_internet_gateway" "eks_igw" {
  vpc_id = aws_vpc.eks_vpc.id

  tags = {
    Name = "eks-igw"
  }
}

resource "aws_route_table" "eks_public_route_table" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks_igw.id
  }

  tags = {
    Name = "eks-public-route-table"
  }
}

resource "aws_route_table_association" "eks_public_route_table_assoc" {
  subnet_id      = aws_subnet.eks_public_subnet.id
  route_table_id = aws_route_table.eks_public_route_table.id
}

# Crear Elastic IP para el NAT Gateway
resource "aws_eip" "eks_nat_eip" {

  tags = {
    Name = "eks-nat-eip"
  }
}

# Crear NAT Gateway en la subnet pública
resource "aws_nat_gateway" "eks_nat_gw" {
  allocation_id = aws_eip.eks_nat_eip.id
  subnet_id     = aws_subnet.eks_public_subnet.id

  tags = {
    Name = "eks-nat-gw"
  }
}

# Crear tabla de rutas para la subnet privada que utilice el NAT Gateway
resource "aws_route_table" "eks_private_route_table" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.eks_nat_gw.id
  }

  tags = {
    Name = "eks-private-route-table"
  }
}

# Asociar la tabla de rutas privada con la subnet privada
resource "aws_route_table_association" "eks_private_route_table_assoc" {
  subnet_id      = aws_subnet.eks_private_subnet.id
  route_table_id = aws_route_table.eks_private_route_table.id
}

resource "aws_eks_cluster" "eks_cluster" {
  name     = "eks-devsu"
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids = [aws_subnet.eks_private_subnet.id, aws_subnet.eks_public_subnet.id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.eks_cluster_AmazonEKSVPCResourceController
  ]
}

resource "aws_iam_role" "eks_cluster_role" {
  name = "eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSVPCResourceController" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_iam_role" "eks_fargate_profile_role" {
  name = "devsu-eks-fargate-profile-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks-fargate-pods.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_fargate_AmazonEKSFargatePodExecutionRolePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
  role       = aws_iam_role.eks_fargate_profile_role.name
}

resource "aws_eks_fargate_profile" "eks_fargate_profile" {
  cluster_name          = aws_eks_cluster.eks_cluster.name
  fargate_profile_name  = "devsu-eks-fargate-profile"
  pod_execution_role_arn = aws_iam_role.eks_fargate_profile_role.arn

  subnet_ids = [aws_subnet.eks_private_subnet.id]

  selector {
    namespace = "default"
  }

  depends_on = [aws_iam_role_policy_attachment.eks_fargate_AmazonEKSFargatePodExecutionRolePolicy]
}

output "cluster_endpoint" {
  value = aws_eks_cluster.eks_cluster.endpoint
}

output "cluster_ca_certificate" {
  value = aws_eks_cluster.eks_cluster.certificate_authority[0].data
}

data "aws_availability_zones" "available" {
  state = "available"
}
