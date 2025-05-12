
provider "aws" {
  region = "us-east-1"
}

resource "aws_budgets_budget" "monthly_budget" {
  name              = "MonthlyBudget"
  budget_type       = "COST"
  limit_amount      = "100"
  limit_unit        = "USD"
  time_unit         = "MONTHLY"

  cost_filters = {
    Service = "AmazonEC2"
  }

  notification {
    comparison_operator = "GREATER_THAN"
    threshold           = 80
    threshold_type      = "PERCENTAGE"
    notification_type   = "ACTUAL"

    subscriber {
      address          = "admin@example.com"
      subscription_type = "EMAIL"
    }
  }
}

resource "aws_instance" "spot_instance" {
  ami                    = "ami-0c02fb55956c7d316"
  instance_type          = "t3.micro"
  instance_market_options {
    market_type = "spot"
  }

  tags = {
    Name = "spot-optimized"
    Env  = "cost-lab"
  }
}
