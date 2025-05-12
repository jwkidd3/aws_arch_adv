
provider "aws" {
  region = "us-east-1"
}

resource "aws_customer_gateway" "example" {
  bgp_asn    = 65000
  ip_address = "198.51.100.1"
  type       = "ipsec.1"
  tags = {
    Name = "OnPremCustomerGateway"
  }
}

resource "aws_vpn_gateway" "example" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "MyVPNGateway"
  }
}

resource "aws_vpn_connection" "example" {
  customer_gateway_id = aws_customer_gateway.example.id
  vpn_gateway_id      = aws_vpn_gateway.example.id
  type                = "ipsec.1"

  static_routes_only = true

  tags = {
    Name = "ExampleVPNConnection"
  }
}
