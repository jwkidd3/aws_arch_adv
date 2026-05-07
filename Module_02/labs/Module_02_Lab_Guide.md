# Lab 2 — Organizations, SCPs, and IAM Identity Center

## Objective

Experience the **multi-account Org from inside a member account**. Watch a Service Control Policy attach and propagate without you doing anything in your own account — that's the durable lesson. Then explore IAM Identity Center as the front door.

## Time budget: 50 minutes

## Pre-flight

1. Sign in via the AWS access portal → `Sandbox<N>` → `AWSAdministratorAccess`.
2. Region selector: `us-east-1`.

## Part A — Confirm your starting state (5 min)

1. **AWS Organizations** from a Sandbox account shows a **read-only summary** — you can confirm you're part of the org and see the management account ID, but you can't see other accounts, OUs, or policies. That's expected — only the management account owns the Org.
2. **IAM Identity Center** is also managed centrally. From your access portal page, note:
   - The portal URL itself (`d-xxxxxxxxxx.awsapps.com/start`)
   - That you only see `Sandbox<N>` listed (no other student's account)
   - The `AWSAdministratorAccess` permission set the instructor assigned
3. Inside your Sandbox, open **IAM** and confirm there is a small set of identity-center-managed roles (named `AWSReservedSSO_AWSAdministratorAccess_*`). Do not modify these — they are managed from the management account.

## Part B — Region restriction SCP (live demo, 25 min)

This part runs as a **synchronized class demo**. The instructor drives from the management account; you drive from your Sandbox.

1. **Step 1 (you):** Open **EC2** and switch the region selector to **`eu-west-1`**.
2. Click **Launch instance**. Name `archadv-<your-name>-region-test`. AMI: Amazon Linux 2023, `t3.micro`. **Launch.** It should succeed.
3. Terminate that instance.
4. **Step 2 (instructor):** Attaches the staged `DenyNonApprovedRegions` SCP to the Sandbox OU. Counts down "3, 2, 1, attached" — wait for the cue.
5. **Step 3 (you):** Repeat the launch in `eu-west-1`. It fails with `UnauthorizedOperation` (the underlying reason — visible in the encoded auth-failure message and in CloudTrail — is an explicit deny from the SCP). If the first retry still succeeds, wait ~10–30 sec and retry: SCP propagation is documented as immediate but can take a few seconds in practice.
6. Switch the region selector to `us-east-1`. Launch the same instance type. **Succeeds** — the SCP only denies non-approved regions.
7. Terminate the `us-east-1` instance.
8. **Step 4 (instructor):** Detaches the SCP. Counts down "3, 2, 1, detached".
9. **Step 5 (you):** Switch back to `eu-west-1` and launch again. Succeeds.

## Part C — Inspect IAM Identity Center attribution (5 min)

1. In your Sandbox, open **CloudTrail → Event history**. Filter for **Event name = RunInstances** (the User name filter is exact-match on your IdC session name — easier to filter by event).
2. Find the `RunInstances` events from Part B. Note the `userIdentity.arn` — it ends in `AWSReservedSSO_AWSAdministratorAccess_<id>/<your-username>`. That's how Org-level audit attributes actions back to the IAM IdC user, even though the call ran in your member account.

## Part D — Tag-required SCP (stretch, 10 min)

Time permitting, the instructor attaches a second SCP requiring `Owner` tag on EC2 launches:

1. Try to launch an EC2 with no tags → denied.
2. Add `Owner=<your-name>` and `Course=archadv` tags during launch → succeeds.
3. Instructor detaches the SCP.

## Validation checklist

- [ ] You experienced the `eu-west-1` launch succeeding, then failing under SCP, then succeeding after detach
- [ ] You can locate the failed `RunInstances` event in CloudTrail
- [ ] You can describe in one sentence the difference between an **IAM policy** and an **SCP**
- [ ] You can describe in one sentence the difference between **IAM Identity Center** and standalone **IAM users**

## Discussion prompts

- Where would the deny-non-approved-regions SCP belong in *your* org — at the root, at an OU, or per-account? Why?
- What goes in a Sandbox OU vs a Prod OU vs a Security OU? What SCPs differ?

## Cleanup

Nothing to clean up — the demo instances were already terminated.

## Stretch goals

- From the access portal, switch into **a different IAM IdC permission set** if your user has more than one assigned (some orgs split admin / read-only).
- Read the **AWS Organizations service authorization reference** and find one action you would deny at the Org root regardless of OU.
