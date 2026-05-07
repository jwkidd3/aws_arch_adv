# Lab 4 — Storage Gateway + DataSync

## Objective

Stand up a **File Gateway** in your Sandbox account and use **DataSync** to move on-prem-shaped data into S3. This is the basic "hybrid storage" pattern: legacy systems write to NFS/SMB; AWS sees objects in S3.

## Time budget: 70 minutes (was 50 — File Gateway and DataSync each take longer than the docs suggest)

## Pre-flight

1. Sign in to `Sandbox<N>`. Region `us-east-1`.
2. You should have a VPC from Lab 1.

## Part A — File Gateway (25 min)

The File Gateway runs as an EC2 instance inside your Sandbox. In the real world it runs on-prem; deploying it as EC2 is the supported pattern for testing and is what AWS itself recommends for an in-cloud demo.

### 1. Destination S3 bucket (2 min)

- **S3 → Create bucket**
- Name: `archadv-<your-name>-filegw`
- Region: `us-east-1`
- Block all public access: **on**
- SSE: **Amazon S3 managed (SSE-S3)**
- Tag: `Owner`, `Course=archadv`
- Create.

### 2. Launch the gateway VM (5 min)

- **Storage Gateway → Create gateway**
- Gateway type: **Amazon S3 File Gateway**
- Host platform: **Amazon EC2** → **Launch instance**
- Console hands you off to EC2 with the right AMI pre-selected:
  - AMI: AWS Storage Gateway (auto-selected)
  - Instance: `m5.xlarge` (the minimum supported size — this is real money during the lab; we cap the lab at 25 min for this part)
  - Key pair: `archadv-<your-name>` (from Lab 1)
  - Network: your VPC, **public subnet**
  - Auto-assign public IP: enable
  - Security group: new — allow `80/tcp` from **My IP** for activation, and all traffic from the **gateway's own SG** (loopback)
  - **Configure storage:** add a **150 GiB gp3** EBS volume in addition to the root volume. This is the gateway's cache disk and is **required** for activation; if you skip it, you'll have to stop the EC2 and add it later.
- Launch the EC2. Note its public IP. (If your classroom is behind a proxy that blocks port 80 outbound, activation fails — switch to a different network.)

### 3. Activate the gateway (5 min)

- Back in **Storage Gateway → Create gateway → Connect**
- IP address of gateway: the EC2's **public IP**
- Activate. (Wait ~2 min while the activation API is called.)
- Configure local disks: select the 150 GiB volume you attached in step 2 as **Cache**.
- Activate gateway. Wait ~3 min until status `Running`.

### 4. Create the file share (3 min)

- **Storage Gateway → File shares → Create file share**
- Choose **Customize configuration** (vs Quick create) so you can set the IAM role and access pattern.
- Gateway: yours
- Amazon S3 bucket: `archadv-<your-name>-filegw`
- Access: **NFS**
- IAM role: **Create new role** (Storage Gateway service role)
- Allowed clients: `0.0.0.0/0` for the lab (do not do this in production)
- Create.

### 5. Mount and write (5 min)

SSH into your bastion EC2 (Lab 1). From the bastion:

```bash
sudo dnf install -y nfs-utils
sudo mkdir -p /mnt/fgw
sudo mount -t nfs -o nolock,hard <gateway-public-ip>:/archadv-<your-name>-filegw /mnt/fgw

echo "hello from on-prem" | sudo tee /mnt/fgw/hello.txt
ls -la /mnt/fgw/
```

In the **S3 console**, refresh `archadv-<your-name>-filegw`. You should see `hello.txt` materialized as an object within ~30 sec.

### 6. Validate the round-trip (5 min)

- From the S3 console, upload a second object directly to the bucket: `cloud-side.txt`.
- On the bastion, `ls /mnt/fgw/`. The new object should appear within ~30 sec via the gateway's cache refresh.

## Part B — DataSync (15 min)

### 1. Create source location (3 min)

- **DataSync → Locations → Create location**
- Type: **NFS**
- Agent: **Create agent → Amazon EC2** (yes, another agent VM — DataSync requires its own; in production this is on-prem)
  - **Use `m5.2xlarge`** — the DataSync agent will not boot/activate below this floor (per `docs.aws.amazon.com/datasync/latest/userguide/agent-requirements.html`). For >20M files in production, scale to `m5.4xlarge`.
  - Same VPC and public subnet
- Activation: same flow as Storage Gateway (use the agent's public IP)
- After agent is `Online`: NFS server `<bastion-private-ip>`, mount path `/home/ec2-user`
- Create location.

### 2. Create destination location (1 min)

- **DataSync → Locations → Create location**
- Type: **S3**
- Bucket: `archadv-<your-name>-filegw` (reuse), prefix `datasync/` (no leading slash — S3 prefixes don't start with `/`)
- IAM role: **Auto-generate**
- Create.

### 3. Create the task (2 min)

- **DataSync → Tasks → Create task**
- Source: the NFS location
- Destination: the S3 location
- Settings: defaults (verify only changed data, log to CloudWatch)
- Create.

### 4. Run the task twice (5 min)

- **Start with defaults.** Wait ~1 min. Confirm files from `/home/ec2-user` appear in `s3://archadv-<your-name>-filegw/datasync/`.
- Add a new file on the bastion: `echo new > /home/ec2-user/delta.txt`.
- **Run the task again.** This time DataSync should report **only `delta.txt` transferred** — that's the production delta-sync pattern.

## Validation checklist

- [ ] File Gateway is `Running` and has an NFS share pointed at your bucket
- [ ] Files written to NFS appear in S3 within ~30 sec
- [ ] Files written to S3 appear via NFS within ~30 sec
- [ ] DataSync agent is `Online`
- [ ] Initial DataSync task copied multiple files
- [ ] Second DataSync task copied **only the delta**

## Cleanup

In this order:

1. Delete the DataSync task and locations.
2. Delete the File Gateway file share.
3. Delete the gateway in Storage Gateway console (keeps the EC2 — terminate the EC2 manually).
4. Empty and delete the S3 bucket.
5. Terminate both EC2s (gateway + DataSync agent).

## Stretch goals

- Schedule the DataSync task to run hourly. Confirm CloudWatch logs of subsequent runs.
- Replace SSE-S3 on the bucket with **SSE-KMS** using a customer-managed key. Confirm the gateway still writes successfully — the role policy needs `kms:GenerateDataKey`.
