# State Bootstrap

Creates the S3 bucket that `environments/*` use as their remote state
backend. This is the one legitimate place in this project that uses local
state on purpose — Terraform's own `backend "s3"` block can't point at a
bucket that Terraform itself hasn't created yet, so this one root is applied
manually, once, before any environment is ever initialized.

**Not run yet.** This project is still in the "write and validate the code"
phase — see the main README's Phase 5/6 notes. When it's time to actually
provision:

```bash
cd terraform/bootstrap
terraform init
terraform apply -var="bucket_name=<globally-unique-name>"
```

Then update `terraform/environments/dev/backend.tf`'s `bucket` value to match
before running `terraform init` (without `-backend=false`) in that directory.

**Cost:** an S3 bucket holding a few small JSON state files costs cents/month
(well under $0.01 for the data itself; S3 has no bucket-existence charge).
**Teardown:** `terraform destroy` in this directory — but only after every
environment using it as a backend has been destroyed first, and note the
`prevent_destroy` lifecycle rule in `main.tf` requires that block removed (or
`terraform state rm`'d) before destroy will proceed at all. This is
deliberate friction: it's much harder to accidentally delete the bucket
holding every environment's state.
