#!/bin/bash

set -e

REGION="${1:-eu-central-1}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")

if [ -z "$AWS_ACCOUNT_ID" ]; then
  echo "Error: Could not determine AWS account ID. Ensure AWS credentials are configured."
  exit 1
fi

BUCKET_NAME="petclinic-terraform-state-${AWS_ACCOUNT_ID}"
TABLE_NAME="petclinic-terraform-locks"

echo "🚀 Bootstrapping Terraform state infrastructure..."
echo "   Region: $REGION"
echo "   Account: $AWS_ACCOUNT_ID"
echo "   S3 Bucket: $BUCKET_NAME"
echo "   DynamoDB Table: $TABLE_NAME"

# Check if bucket exists, if not create it
if aws s3 ls "s3://${BUCKET_NAME}" --region "$REGION" 2>&1 | grep -q 'NoSuchBucket'; then
  echo "📦 Creating S3 bucket..."
  if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket \
      --bucket "$BUCKET_NAME" \
      --region "$REGION" \
      2>/dev/null || echo "   Bucket may already exist"
  else
    aws s3api create-bucket \
      --bucket "$BUCKET_NAME" \
      --region "$REGION" \
      --create-bucket-configuration LocationConstraint="$REGION" \
      2>/dev/null || echo "   Bucket may already exist"
  fi
else
  echo "✅ S3 bucket already exists"
fi

# Enable versioning
echo "🔄 Enabling S3 versioning..."
aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --region "$REGION" \
  --versioning-configuration Status=Enabled \
  2>/dev/null || echo "   Versioning may already be enabled"

# Enable server-side encryption
echo "🔐 Enabling S3 server-side encryption..."
aws s3api put-bucket-encryption \
  --bucket "$BUCKET_NAME" \
  --region "$REGION" \
  --server-side-encryption-configuration '{
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        }
      }
    ]
  }' \
  2>/dev/null || echo "   Encryption may already be enabled"

# Block all public access
echo "🛡️  Blocking all public access..."
aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --region "$REGION" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
  2>/dev/null || echo "   Public access may already be blocked"

# Create DynamoDB table if it doesn't exist
echo "📋 Checking DynamoDB table..."
if ! aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$REGION" 2>/dev/null | grep -q "ACTIVE\|CREATING"; then
  echo "📝 Creating DynamoDB table..."
  aws dynamodb create-table \
    --table-name "$TABLE_NAME" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$REGION" \
    2>/dev/null || echo "   Table may already exist"

  # Wait for table to be active
  echo "⏳ Waiting for DynamoDB table to be active..."
  aws dynamodb wait table-exists \
    --table-name "$TABLE_NAME" \
    --region "$REGION" \
    2>/dev/null || true
else
  echo "✅ DynamoDB table already exists"
fi

echo ""
echo "✨ Bootstrap complete!"
echo ""
echo "Next steps:"
echo "1. Initialize Terraform in each environment:"
echo "   cd terraform/environments/dev && terraform init"
echo "   cd terraform/environments/prod && terraform init"
echo ""
