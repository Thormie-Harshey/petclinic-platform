terraform {
  backend "s3" {
    bucket         = "petclinic-terraform-state-<YOUR-ACCOUNT-ID>"
    key            = "petclinic/prod/terraform.tfstate"
    region         = "eu-central-1"
    encrypt        = true
    dynamodb_table = "petclinic-terraform-locks"
  }
}
