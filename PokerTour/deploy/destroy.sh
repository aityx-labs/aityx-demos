#!/usr/bin/env bash
# Removes the Poker Tour stack from AWS: empties the web bucket (a stack
# can't delete a bucket with objects in it), deletes the stack, and says
# what is left on purpose: the data bucket, with the leaderboard and the
# key (DeletionPolicy Retain), and the code bucket.
#
#   bash deploy/destroy.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../scripts/env.sh
source "$root/scripts/env.sh"
stack="${POKERTOUR_STACK:-pokertour}"
region="${AWS_REGION:-$(aws configure get region || true)}"
account="$(aws sts get-caller-identity --query Account --output text)"
web_bucket="${stack}-web-${account}"
if aws s3api head-bucket --bucket "$web_bucket" --region "$region" >/dev/null 2>&1; then
  echo "destroy: emptying s3://$web_bucket"
  aws s3 rm --quiet --recursive "s3://$web_bucket" --region "$region"
fi
echo "destroy: deleting the stack $stack"
aws cloudformation delete-stack --stack-name "$stack" --region "$region"
aws cloudformation wait stack-delete-complete --stack-name "$stack" --region "$region"
cat <<MSG
Gone. Kept, on purpose: the data bucket s3://${stack}-data-${account} (the
leaderboard, the key) and the code bucket s3://${stack}-code-${account}-${region};
remove them with aws s3 rb --force when they are no longer wanted.
MSG
