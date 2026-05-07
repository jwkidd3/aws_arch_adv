#!/usr/bin/env bash
# Lab 6 assertions — ECR + ECS Fargate + ALB.

set -uo pipefail

cd "$(dirname "$0")"

if ! TF_OUT=$(terraform output -json 2>/dev/null); then
  echo "ERROR: terraform output failed" >&2
  exit 2
fi

ALB_DNS=$(echo  "$TF_OUT" | jq -r '.alb_dns.value')
ALB_ARN=$(echo  "$TF_OUT" | jq -r '.alb_arn.value')
TG_ARN=$(echo   "$TF_OUT" | jq -r '.tg_arn.value')
CLUSTER=$(echo  "$TF_OUT" | jq -r '.cluster_name.value')
SERVICE=$(echo  "$TF_OUT" | jq -r '.service_name.value')
ECR=$(echo      "$TF_OUT" | jq -r '.ecr_repo.value')

PASS=0; FAIL=0
pass() { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*" >&2; FAIL=$((FAIL+1)); }

echo "==> Lab 6 — ECR + ECS Fargate + ALB"

# 1. ECR repository exists
ECR_URI=$(aws ecr describe-repositories --repository-names "$ECR" \
  --query 'repositories[0].repositoryUri' --output text 2>/dev/null || echo "")
[[ "$ECR_URI" == *.dkr.ecr.*.amazonaws.com/* ]] \
  && pass "ECR repo exists: $ECR_URI" \
  || fail "ECR repo lookup failed"

# 2. ECS cluster is ACTIVE
CLUSTER_STATUS=$(aws ecs describe-clusters --clusters "$CLUSTER" \
  --query 'clusters[0].status' --output text 2>/dev/null || echo "")
[[ "$CLUSTER_STATUS" == "ACTIVE" ]] && pass "ECS cluster ACTIVE" || fail "cluster status: $CLUSTER_STATUS"

# 3. Wait for service to stabilize (desired = running) — up to 6 min
echo "  Waiting for ECS service to stabilize..."
for _ in $(seq 1 36); do
  RUNNING=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
    --query 'services[0].runningCount' --output text 2>/dev/null || echo "0")
  DESIRED=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
    --query 'services[0].desiredCount' --output text 2>/dev/null || echo "0")
  [[ "$RUNNING" == "$DESIRED" && "$RUNNING" -ge 1 ]] && break
  sleep 10
done
[[ "$RUNNING" -ge 2 ]] \
  && pass "ECS service running: $RUNNING/$DESIRED tasks" \
  || fail "ECS service: $RUNNING running, $DESIRED desired (after 6 min)"

# 4. Targets are healthy in TG
HEALTHY=$(aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
  --query "TargetHealthDescriptions[?TargetHealth.State=='healthy'] | length(@)" --output text 2>/dev/null || echo "0")
[[ "$HEALTHY" -ge 2 ]] \
  && pass "$HEALTHY targets healthy in TG" \
  || fail "only $HEALTHY targets healthy"

# 5. ALB returns 200 on / (the public nginx default page)
sleep 3
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://${ALB_DNS}/" || echo "000")
[[ "$HTTP_CODE" == "200" ]] \
  && pass "ALB returns HTTP 200" \
  || fail "ALB returns $HTTP_CODE (expected 200)"

# 6. Task uses awsvpc network mode (Fargate requirement) and private subnets
NETWORK_MODE=$(aws ecs describe-task-definition --task-definition archadv-ci-lab06-hello \
  --query 'taskDefinition.networkMode' --output text 2>/dev/null || echo "")
[[ "$NETWORK_MODE" == "awsvpc" ]] && pass "task network mode: awsvpc" || fail "network mode: $NETWORK_MODE"

# 7. Tasks have NO public IP
TASK_ARN=$(aws ecs list-tasks --cluster "$CLUSTER" --service-name "$SERVICE" \
  --query 'taskArns[0]' --output text 2>/dev/null || echo "")
if [[ -n "$TASK_ARN" && "$TASK_ARN" != "None" ]]; then
  ENI_PUB=$(aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$TASK_ARN" \
    --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' --output text 2>/dev/null)
  if [[ -n "$ENI_PUB" ]]; then
    PUB_IP=$(aws ec2 describe-network-interfaces --network-interface-ids "$ENI_PUB" \
      --query 'NetworkInterfaces[0].Association.PublicIp' --output text 2>/dev/null || echo "None")
    [[ "$PUB_IP" == "None" || -z "$PUB_IP" ]] \
      && pass "task ENI has no public IP" \
      || fail "task ENI has public IP: $PUB_IP"
  fi
fi

echo
echo "==> Lab 6: $PASS passed, $FAIL failed"
exit $(( FAIL > 0 ? 1 : 0 ))
