data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  az_count = length(var.azs)

  # Subnets are carved sequentially out of the VPC range: public first, then
  # private, then intra. Keeping the layout deterministic makes CIDRs stable
  # when AZs are added later.
  public_subnet_cidrs  = [for i in range(local.az_count) : cidrsubnet(var.cidr_block, var.subnet_newbits, i)]
  private_subnet_cidrs = [for i in range(local.az_count) : cidrsubnet(var.cidr_block, var.subnet_newbits, i + local.az_count)]
  intra_subnet_cidrs   = [for i in range(local.az_count) : cidrsubnet(var.cidr_block, var.subnet_newbits, i + 2 * local.az_count)]

  nat_gateway_count = {
    none   = 0
    single = 1
    per_az = local.az_count
  }[var.nat_gateway_mode]

  create_flow_log_key = var.enable_flow_logs && var.flow_log_kms_key_arn == null
  flow_log_group_name = "/aws/vpc-flow-logs/${var.name}"
  flow_log_group_arn  = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:${local.flow_log_group_name}"

  tags = merge(var.tags, { "platform:module" = "vpc" })
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = var.name })
}

# The default security group allows all traffic between members. Strip every
# rule so nothing can accidentally rely on it.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name}-default-deny" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = var.name })
}

################################################################################
# Subnets
################################################################################

resource "aws_subnet" "public" {
  count = local.az_count

  vpc_id                  = aws_vpc.this.id
  availability_zone       = var.azs[count.index]
  cidr_block              = local.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = false

  tags = merge(local.tags, {
    Name            = "${var.name}-public-${var.azs[count.index]}"
    "platform:tier" = "public"
  })
}

resource "aws_subnet" "private" {
  count = local.az_count

  vpc_id            = aws_vpc.this.id
  availability_zone = var.azs[count.index]
  cidr_block        = local.private_subnet_cidrs[count.index]

  tags = merge(local.tags, {
    Name            = "${var.name}-private-${var.azs[count.index]}"
    "platform:tier" = "private"
  })
}

# Intra subnets have no route to the internet in either direction. They host
# data stores (RDS) and anything else that must never egress.
resource "aws_subnet" "intra" {
  count = local.az_count

  vpc_id            = aws_vpc.this.id
  availability_zone = var.azs[count.index]
  cidr_block        = local.intra_subnet_cidrs[count.index]

  tags = merge(local.tags, {
    Name            = "${var.name}-intra-${var.azs[count.index]}"
    "platform:tier" = "intra"
  })
}

################################################################################
# Routing
################################################################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name}-public" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = local.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  count = local.nat_gateway_count

  domain = "vpc"

  tags = merge(local.tags, { Name = "${var.name}-nat-${var.azs[count.index]}" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count = local.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.tags, { Name = "${var.name}-${var.azs[count.index]}" })

  depends_on = [aws_internet_gateway.this]
}

# One route table per AZ so per-AZ NAT can be switched on without replacing
# associations.
resource "aws_route_table" "private" {
  count = local.az_count

  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name}-private-${var.azs[count.index]}" })
}

resource "aws_route" "private_nat" {
  count = local.nat_gateway_count > 0 ? local.az_count : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[var.nat_gateway_mode == "per_az" ? count.index : 0].id
}

resource "aws_route_table_association" "private" {
  count = local.az_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_route_table" "intra" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${var.name}-intra" })
}

resource "aws_route_table_association" "intra" {
  count = local.az_count

  subnet_id      = aws_subnet.intra[count.index].id
  route_table_id = aws_route_table.intra.id
}

################################################################################
# Flow logs
################################################################################

resource "aws_kms_key" "flow_logs" {
  count = local.create_flow_log_key ? 1 : 0

  description             = "Encrypts VPC flow logs for ${var.name}"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "CloudWatchLogsUse"
        Effect    = "Allow"
        Principal = { Service = "logs.${data.aws_region.current.region}.amazonaws.com" }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*",
        ]
        Resource = "*"
        Condition = {
          ArnEquals = { "kms:EncryptionContext:aws:logs:arn" = local.flow_log_group_arn }
        }
      },
    ]
  })

  tags = merge(local.tags, { Name = "${var.name}-flow-logs" })
}

resource "aws_kms_alias" "flow_logs" {
  count = local.create_flow_log_key ? 1 : 0

  name          = "alias/${var.name}-flow-logs"
  target_key_id = aws_kms_key.flow_logs[0].key_id
}

resource "aws_cloudwatch_log_group" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name              = local.flow_log_group_name
  retention_in_days = var.flow_log_retention_days
  kms_key_id        = local.create_flow_log_key ? aws_kms_key.flow_logs[0].arn : var.flow_log_kms_key_arn

  tags = local.tags
}

resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name_prefix = "${substr(var.name, 0, 20)}-flow-logs-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })

  tags = local.tags
}

# Scoped to the single log group; flow logs never need wildcard log access.
resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name = "write-flow-logs"
  role = aws_iam_role.flow_logs[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams",
      ]
      Resource = ["${local.flow_log_group_arn}:*"]
    }]
  })
}

resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id                   = aws_vpc.this.id
  traffic_type             = var.flow_log_traffic_type
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow_logs[0].arn
  iam_role_arn             = aws_iam_role.flow_logs[0].arn
  max_aggregation_interval = 60

  tags = merge(local.tags, { Name = var.name })
}
