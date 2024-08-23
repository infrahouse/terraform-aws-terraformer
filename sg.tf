resource "aws_security_group" "terraformer" {
  description = "Access to Terraformer"
  name_prefix = "terraformer-"
  vpc_id      = data.aws_vpc.selected.id
  tags = {
    Name : "terraformer"
  }
}

resource "aws_vpc_security_group_ingress_rule" "terraformer_ssh" {
  description       = "Allow SSH traffic"
  security_group_id = aws_security_group.terraformer.id
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = data.aws_vpc.selected.cidr_block
  tags = merge(
    {
      Name = "SSH access"
    },
    local.tags
  )
}

resource "aws_vpc_security_group_ingress_rule" "icmp" {
  description       = "Allow all ICMP traffic"
  security_group_id = aws_security_group.terraformer.id
  from_port         = -1
  to_port           = -1
  ip_protocol       = "icmp"
  cidr_ipv4         = "0.0.0.0/0"
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
