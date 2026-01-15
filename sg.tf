resource "aws_security_group" "terraformer" {
  description = "Access to Terraformer"
  name_prefix = "terraformer-"
  vpc_id      = data.aws_vpc.selected.id
  tags = merge(
    {
      Name : "terraformer"
    },
    local.tags
  )
}

resource "aws_vpc_security_group_ingress_rule" "terraformer_ssh" {
  description       = "Allow SSH traffic from VPC"
  security_group_id = aws_security_group.terraformer.id
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = data.aws_vpc.selected.cidr_block
  tags = merge(
    {
      Name = "SSH from VPC"
    },
    local.tags
  )
}

resource "aws_vpc_security_group_ingress_rule" "terraformer_ssh_extra" {
  for_each = toset(var.extra_ssh_cidrs)

  description       = "Allow SSH traffic from ${each.value}"
  security_group_id = aws_security_group.terraformer.id
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
  tags = merge(
    {
      Name = "SSH from ${each.value}"
    },
    local.tags
  )

  lifecycle {
    precondition {
      condition     = each.value != data.aws_vpc.selected.cidr_block
      error_message = "CIDR ${each.value} duplicates VPC CIDR ${data.aws_vpc.selected.cidr_block}. Remove it from extra_ssh_cidrs as VPC access is already allowed."
    }
  }
}

resource "aws_vpc_security_group_ingress_rule" "icmp" {
  description       = "Allow ICMP traffic from VPC"
  security_group_id = aws_security_group.terraformer.id
  from_port         = -1
  to_port           = -1
  ip_protocol       = "icmp"
  cidr_ipv4         = data.aws_vpc.selected.cidr_block
  tags = merge(
    {
      Name = "ICMP traffic"
    },
    local.tags
  )
}

resource "aws_vpc_security_group_egress_rule" "terraformer_outgoing" {
  security_group_id = aws_security_group.terraformer.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  tags = merge(
    {
      Name = "outgoing traffic"
    },
    local.tags
  )
}
