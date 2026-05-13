# Lab 7 — CodePipeline → CodeBuild → CodeDeploy

## Objective

Wire an AWS-native CI/CD pipeline that builds a new container image and deploys it to the ECS service from Lab 6. Then switch the deploy strategy from rolling to **canary** and watch traffic split.

## Time budget: 65 minutes

## Pre-flight

1. Sign in to `Sandbox<N>`. Region `us-east-1`.
2. The ECS service `archadv-<you>-hello-svc` from Lab 6 must still be running. If you cleaned it up, redo Lab 6 quickly first.
3. Open CloudShell.

## Steps

### 1. Create the CodeCommit repository (3 min)

- **CodeCommit → Repositories → Create repository**
- Name: `archadv-<you>-hello`
- Create.

In CloudShell:

```bash
git config --global user.name "<you>"
git config --global user.email "<you>@example.com"

# IAM Identity Center sessions use rotating credentials. The codecommit-credential-helper
# does not support these. Use git-remote-codecommit instead.
pip3 install --user git-remote-codecommit

git clone codecommit::us-east-1://archadv-<you>-hello
cd archadv-<you>-hello

cat > Dockerfile <<'EOF'
FROM public.ecr.aws/docker/library/nginx:1.27-alpine
RUN echo '<h1>archadv hello pipeline v3</h1>' > /usr/share/nginx/html/index.html
EOF

cat > buildspec.yml <<'EOF'
version: 0.2
phases:
  pre_build:
    commands:
      - REPO=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$IMAGE_REPO
      - aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
  build:
    commands:
      - docker build -t $IMAGE_REPO:$CODEBUILD_RESOLVED_SOURCE_VERSION .
      - docker tag $IMAGE_REPO:$CODEBUILD_RESOLVED_SOURCE_VERSION $REPO:latest
      - docker push $REPO:latest
  post_build:
    commands:
      - printf '[{"name":"web","imageUri":"%s"}]' $REPO:latest > imagedefinitions.json
artifacts:
  files: imagedefinitions.json
EOF

git add . && git commit -m "init"
git push
```

### 2. Create the CodeBuild project (5 min)

- **CodeBuild → Build projects → Create project**
- Name: `archadv-<you>-build`
- Source: AWS CodeCommit, repository `archadv-<you>-hello`, branch `main`
- Environment: Managed image, Amazon Linux 2, `aws/codebuild/amazonlinux2-x86_64-standard:5.0`
- **Privileged: enable** (needed for Docker)
- Service role: **Create new**
- Environment variables:
  - `AWS_ACCOUNT_ID` = your account number
  - `AWS_REGION` = us-east-1
  - `IMAGE_REPO` = `archadv-<you>-hello`
- Buildspec: use the buildspec.yml in the source
- Create.

After creation, attach the inline policy `AmazonEC2ContainerRegistryPowerUser` to the build role (find the role in IAM, attach `AmazonEC2ContainerRegistryPowerUser`).

### 3. Smoke-test the build (3 min)

- CodeBuild → `archadv-<you>-build` → **Start build**.
- Watch **Build log**. Should succeed in ~3 min.
- Confirm a new `:latest` image in ECR.

### 4. Create the artifact bucket (1 min)

- **S3 → Create bucket**: `archadv-<you>-pipeline-artifacts`. Block public access. Tag.

### 5. Create the CodePipeline (5 min)

- **CodePipeline → Pipelines → Create pipeline**
- Pipeline name: `archadv-<you>-pipeline`
- Service role: **New**, name auto
- Artifact store: custom location, the bucket from step 4
- Source provider: AWS CodeCommit, repository `archadv-<you>-hello`, branch `main`, change detection: CloudWatch Events
- Build provider: AWS CodeBuild, project `archadv-<you>-build`
- Deploy provider: **Amazon ECS** (standard, not blue/green for now)
  - Cluster: `archadv-<you>-cluster`
  - Service: `archadv-<you>-hello-svc`
  - Image definitions file: `imagedefinitions.json`
- Create.

The pipeline starts immediately. End-to-end first run: 4–6 min.

### 6. Validate

```bash
ALB=$(aws elbv2 describe-load-balancers --names archadv-<you>-alb --query 'LoadBalancers[0].DNSName' --output text)
curl http://$ALB
# After pipeline completes: <h1>archadv hello pipeline v3</h1>
```

### 7. Trigger a re-deploy from a commit (5 min)

In CloudShell, in your repo:

```bash
sed -i 's/v3/v4/' Dockerfile
git add Dockerfile && git commit -m "v4"
git push
```

Watch the pipeline kick off automatically. After ~4 min, `curl` returns `v4`.

### 8. Switch to blue/green canary deploy (10 min, optional but high-value)

- **CodeDeploy → Applications → Create application**: type ECS.
- **Deployment group**: type ECS, blue/green deployment, target group pair = your existing TG + a new TG2 (create one — same settings as Lab 6).
- Configure traffic shifting: **CodeDeployDefault.ECSCanary10Percent5Minutes** (10% to canary for 5 min, then 100%).
- Update the ECS service to use **CODE_DEPLOY** as the deployment controller (this requires re-creating the service — the console will guide you).
- Re-run the pipeline. Watch the deploy stage:
  - 10% of traffic shifts to TG2 for 5 min
  - Curl in a loop — you should see ~10% `v5` responses for the first 5 min
  - Then 100% shift

## Validation checklist

- [ ] CodeCommit repo has buildspec.yml and Dockerfile
- [ ] CodeBuild project succeeds in standalone build
- [ ] Pipeline runs end-to-end on a commit
- [ ] Pipeline-deployed image visible in ECS service revision history
- [ ] (Optional) Canary deploy splits traffic 10/90 for 5 min before full shift

## Cleanup

1. Delete the pipeline. Delete CodeBuild project.
2. Delete the CodeCommit repository.
3. Delete the CodeDeploy application (if you did step 8).
4. Empty and delete the artifact bucket.
5. Leave ECS for the rest of the day or clean up via Lab 6's cleanup steps.

## Stretch goals

- Add a **manual approval action** between the build and deploy stages.
- Replace CodeCommit with a **GitHub source action** using an **AWS CodeConnections** connection (formerly CodeStar Connections — renamed in 2024). This is what most teams use today.
- Add a CloudWatch alarm on ECS task health and configure CodeDeploy to **auto-rollback** if it fires during the canary window.
