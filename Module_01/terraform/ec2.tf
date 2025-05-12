
resource "aws_instance" "web" {
  ami           = "ami-0c02fb55956c7d316"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public.id
  associate_public_ip_address = true

  tags = {
    Name = "WebServer"
  }
}
