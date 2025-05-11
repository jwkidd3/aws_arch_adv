
provider "aws" {
  region = "us-west-2"
}

resource "aws_instance" "gpu_instance" {
  ami           = "ami-0b2ca94b5b49c8c4d"
  instance_type = "g5.xlarge"
  subnet_id     = "subnet-xxxxxxxx"
  key_name      = "my-key"

  tags = {
    Name = "GPUComputeNode"
  }
}

resource "aws_fsx_lustre_file_system" "example" {
  subnet_ids         = ["subnet-xxxxxxxx"]
  deployment_type    = "SCRATCH_2"
  per_unit_storage_throughput = 200
  storage_capacity    = 1200

  tags = {
    Name = "MyLustreFS"
  }
}
