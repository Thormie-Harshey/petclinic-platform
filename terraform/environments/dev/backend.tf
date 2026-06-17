terraform {
  backend "s3" {
    key     = "petclinic/dev/terraform.tfstate"
    region  = "eu-central-1"
    encrypt = true
    # bucket and dynamodb_table are supplied via backend.hcl (gitignored)
    # Run: terraform init -backend-config=backend.hcl
  }
}
