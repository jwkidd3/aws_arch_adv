# Lab 12 proof harness — STUB

**Status: not yet implemented.**

## Scope when implemented

- Provision a Budget with email notification at 80% Actual and 100% Forecasted
- Validate the Budget exists and has the expected thresholds and recipients
- Optionally: provision a tag (`Course=archadv`) on a small dummy resource and verify it shows up in the Budget filter dropdown (this requires the cost allocation tag to be activated, which is account-level)

## What can NOT be automated

- Cost Explorer activation — Cost Explorer takes ~24 hours to populate; CI cannot prove it works without a stable longitudinal account
- Cost allocation tag activation — also account-level state; CI runs are ephemeral
- Member-account billing access — depends on Org-side configuration the CI Sandbox doesn't model

## Why this is not implemented in the initial harness

Most of Lab 12 is observational. The Budget creation flow is automatable but doesn't catch much that wouldn't already be caught by service-level health checks. Lower priority than Labs 4, 6, 7, 8, 10.

Copy `lab-09-kms-secrets/` as the template.
