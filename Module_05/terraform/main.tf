
provider "aws" {
  region = "us-east-1"
}

resource "aws_ec2_transit_gateway" "tgw" {
  description = "My TGW"
  amazon_side_asn = 64512

  tags = {
    Name = "TGW"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "vpc_a_attach" {
  subnet_ids         = ["subnet-xxxxxxxx"]
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  vpc_id             = "vpc-xxxxxxxx"

  tags = {
    Name = "VPC-A-TGW-Attachment"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "vpc_b_attach" {
  subnet_ids         = ["subnet-yyyyyyyy"]
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  vpc_id             = "vpc-yyyyyyyy"

  tags = {
    Name = "VPC-B-TGW-Attachment"
  }
}
