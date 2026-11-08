#!/bin/sh
# The tour's local bucket and table (deploy/template.yaml's DataBucket and
# Table, as Floci has them), when missing: Floci keeps them in its volume.
set -eu

name=pokertour-local
if ! aws s3api head-bucket --bucket "$name" >/dev/null 2>&1; then
  aws s3 mb "s3://$name" >/dev/null
  echo "pokertour: made the bucket $name"
fi
if ! aws dynamodb describe-table --table-name "$name" >/dev/null 2>&1; then
  aws dynamodb create-table --table-name "$name" \
    --attribute-definitions AttributeName=pk,AttributeType=S AttributeName=sk,AttributeType=S \
    --key-schema AttributeName=pk,KeyType=HASH AttributeName=sk,KeyType=RANGE \
    --billing-mode PAY_PER_REQUEST >/dev/null
  echo "pokertour: made the table $name"
fi
