output "budget_name" {
  value = aws_budgets_budget.lab.name
}

output "account_id" {
  value = data.aws_caller_identity.me.account_id
}

output "alert_email" {
  value = "noreply+lab12@example.com"
}
