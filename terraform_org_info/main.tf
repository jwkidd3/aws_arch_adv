provider "aws" {
  region = "us-east-1"
}

resource "null_resource" "list_accounts" {
  provisioner "local-exec" {
    command = "aws organizations list-accounts --output json > accounts.json"
  }
}
