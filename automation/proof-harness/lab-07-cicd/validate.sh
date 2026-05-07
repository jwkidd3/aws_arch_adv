#!/usr/bin/env bash
# Lab 7 assertions — CodeCommit + CodeBuild + CodePipeline.

set -uo pipefail

cd "$(dirname "$0")"

source "$(cd ../../tools && pwd)/identity.sh"
OWNER=$(derive_owner_slug)

if ! TF_OUT=$(terraform output -json 2>/dev/null); then
  echo "ERROR: terraform output failed" >&2
  exit 2
fi

REPO=$(echo      "$TF_OUT" | jq -r '.repo_name.value')
BUILD=$(echo     "$TF_OUT" | jq -r '.build_project.value')
PIPELINE=$(echo  "$TF_OUT" | jq -r '.pipeline_name.value')
BUCKET=$(echo    "$TF_OUT" | jq -r '.artifact_bucket.value')

PASS=0; FAIL=0
pass() { echo "  PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $*" >&2; FAIL=$((FAIL+1)); }

echo "==> Lab 7 — CodeCommit + CodeBuild + CodePipeline"

# 1. CodeCommit repo exists
REPO_DATA=$(aws codecommit get-repository --repository-name "$REPO" \
  --query 'repositoryMetadata.repositoryName' --output text 2>/dev/null || echo "")
[[ "$REPO_DATA" == "$REPO" ]] \
  && pass "CodeCommit repo exists: $REPO" \
  || fail "CodeCommit repo lookup failed"

# 2. Seed buildspec.yml so the pipeline-triggered CodeBuild has something to run.
# (CodePipeline-driven CodeBuild looks for buildspec.yml in the source artifact;
# the project's inline buildspec is ignored in pipeline mode.)
echo "  Putting initial buildspec.yml in CodeCommit repo..."
BUILDSPEC=$(cat <<'YAML'
version: 0.2
phases:
  build:
    commands:
      - echo "archadv lab 7 harness build"
      - echo "build succeeded at $(date)" > build-output.txt
artifacts:
  files:
    - build-output.txt
YAML
)
BUILDSPEC_B64=$(printf "%s" "$BUILDSPEC" | base64)
COMMIT_RESP=$(aws codecommit put-file \
  --repository-name "$REPO" \
  --branch-name main \
  --file-path buildspec.yml \
  --file-content "$BUILDSPEC_B64" \
  --commit-message "init" 2>&1 || echo "COMMIT_FAILED")

if echo "$COMMIT_RESP" | grep -q "COMMIT_FAILED"; then
  fail "could not seed CodeCommit repo (commit error: $COMMIT_RESP)"
else
  pass "seeded buildspec.yml on main branch"
fi

# 3. CodeBuild project exists with the right image
IMAGE=$(aws codebuild batch-get-projects --names "$BUILD" \
  --query 'projects[0].environment.image' --output text 2>/dev/null || echo "")
[[ "$IMAGE" == *"amazonlinux2-x86_64-standard:5.0" ]] \
  && pass "CodeBuild image: $IMAGE" \
  || fail "CodeBuild image mismatch: $IMAGE"

# 4. CodePipeline exists with Source + Build stages
STAGES=$(aws codepipeline get-pipeline --name "$PIPELINE" \
  --query 'pipeline.stages[].name' --output text 2>/dev/null || echo "")
echo "$STAGES" | grep -q "Source" && pass "Pipeline has Source stage" || fail "Pipeline missing Source stage"
echo "$STAGES" | grep -q "Build"  && pass "Pipeline has Build stage"  || fail "Pipeline missing Build stage"

# DEBUG: dump the pipeline role's policies
echo "  --- Pipeline role policies (debug) ---"
PROLE="archadv-${OWNER}-lab07-pipeline"
aws iam list-role-policies --role-name "$PROLE" --output text 2>/dev/null
for P in $(aws iam list-role-policies --role-name "$PROLE" --query 'PolicyNames' --output text 2>/dev/null); do
  echo "  Policy: $P"
  aws iam get-role-policy --role-name "$PROLE" --policy-name "$P" --query 'PolicyDocument' --output json 2>/dev/null
done

# Wait a moment for IAM propagation if the policy was just deployed
echo "  Sleeping 30s for IAM propagation..."
sleep 30

# 5. Trigger the pipeline (the Source push above may have already auto-triggered;
#    we explicitly start it here in case)
echo "  Starting pipeline execution..."
EXEC_ID=$(aws codepipeline start-pipeline-execution --name "$PIPELINE" \
  --query 'pipelineExecutionId' --output text 2>/dev/null || echo "")
[[ -n "$EXEC_ID" && "$EXEC_ID" != "None" ]] \
  && pass "Pipeline execution started: $EXEC_ID" \
  || fail "could not start pipeline execution"

# 6. Wait for pipeline to reach Succeeded or Failed (up to 8 min)
if [[ -n "$EXEC_ID" ]]; then
  echo "  Waiting for pipeline execution to complete..."
  for _ in $(seq 1 48); do
    STATUS=$(aws codepipeline get-pipeline-execution \
      --pipeline-name "$PIPELINE" --pipeline-execution-id "$EXEC_ID" \
      --query 'pipelineExecution.status' --output text 2>/dev/null || echo "")
    case "$STATUS" in
      Succeeded|Failed|Cancelled|Stopped) break ;;
    esac
    sleep 10
  done
  if [[ "$STATUS" == "Succeeded" ]]; then
    pass "Pipeline execution: Succeeded"
  else
    fail "Pipeline execution: $STATUS"
    echo "    --- Action execution details for diagnosis ---" >&2
    aws codepipeline list-action-executions --pipeline-name "$PIPELINE" \
      --filter "pipelineExecutionId=$EXEC_ID" \
      --query 'actionExecutionDetails[].{Stage:stageName,Action:actionName,Status:status,Error:output.executionResult.externalExecutionSummary,Reason:output.executionResult.externalExecutionId}' \
      --output table >&2 2>/dev/null || true
    aws codepipeline list-action-executions --pipeline-name "$PIPELINE" \
      --filter "pipelineExecutionId=$EXEC_ID" \
      --query 'actionExecutionDetails[].{Stage:stageName,Status:status,Error:output.executionResult.externalExecutionSummary}' \
      --output json >&2 2>/dev/null || true
  fi
fi

# 7. Artifact bucket has at least one object after pipeline run
sleep 3
N_OBJ=$(aws s3 ls "s3://$BUCKET" --recursive 2>/dev/null | wc -l | tr -d ' ')
[[ "$N_OBJ" -ge 1 ]] \
  && pass "artifact bucket has $N_OBJ object(s)" \
  || fail "artifact bucket is empty"

echo
echo "==> Lab 7: $PASS passed, $FAIL failed"
exit $(( FAIL > 0 ? 1 : 0 ))
