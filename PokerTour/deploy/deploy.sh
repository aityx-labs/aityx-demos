#!/usr/bin/env bash
# Deploys Poker Tour to AWS, serverless (deploy/template.yaml):
#   1. builds the app's web build (scripts/build.sh web) and the Lambda
#      functions' executable (docker/lambda.Dockerfile, in Docker, for
#      the functions' architecture), and zips the latter with the models
#   2. uploads the zip to a code bucket of this account and region
#      (<stack>-code-<account>-<region>, made on the first run)
#   3. creates or updates the CloudFormation stack: the data and web
#      buckets, CloudFront, the two functions, the players' role, the
#      EventBridge schedule
#   4. syncs the web build to the web bucket under app/, and invalidates
#      CloudFront
#   5. puts the leaderboard's key, POKERTOUR_PROD_LEADERBOARD_KEY, in the
#      data bucket when its object is missing (or with --key: again),
#      through a pipe, never a command line. Only the functions can read
#      it; players bring their own keys, and never get the host's.
#      Production never gets a local key or AITYX_URL: its address is
#      AITYX_PROD_URL (default https://api.aityx.ai).
# then prints the app's address and the origin to authorize in the Google
# OAuth client.
#
#   bash deploy/deploy.sh [--key] [--no-build]
#
# Settings, from the environment or .env: OIDC_CLIENT_ID or
# POKERTOUR_OIDC_CLIENT_ID (the sign-in; without it nobody can sign in),
# AITYX_PROD_URL and POKERTOUR_PROD_LEADERBOARD_KEY (production's aityx),
# POKERTOUR_ALLOWED_DOMAINS, POKERTOUR_SCHEDULE_HOURS, POKERTOUR_MAX_HANDS,
# POKERTOUR_MAX_ENTRIES; and POKERTOUR_STACK (default
# pokertour), POKERTOUR_TENANCY (the account's tenancy tag: GA, the
# default, RC or shared), AWS_REGION (default the CLI's), LAMBDA_ARCH (arm64, the
# default, or x86_64: Docker builds for it, emulated when it isn't the
# host's). Needs the AWS CLI with credentials for the account, Docker,
# and zip.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../scripts/env.sh
source "$root/scripts/env.sh"

upload_key=no
build=yes
for arg in "$@"; do
  case "$arg" in
    --key) upload_key=yes ;;
    --no-build) build=no ;;
    *)
      echo "usage: bash deploy/deploy.sh [--key] [--no-build]" >&2
      exit 2
      ;;
  esac
done

stack="${POKERTOUR_STACK:-pokertour}"
prod_url="${AITYX_PROD_URL:-https://api.aityx.ai}"
if [[ "$prod_url" == *stage* ]]; then
  echo "error: AITYX_PROD_URL is a staging address ($prod_url): production uses https://api.aityx.ai" >&2
  exit 1
fi
region="${AWS_REGION:-$(aws configure get region || true)}"
if [[ -z "$region" ]]; then
  echo "error: no region: set AWS_REGION or the CLI's default" >&2
  exit 1
fi
arch="${LAMBDA_ARCH:-arm64}"
# The account's tag standard: every resource names its project and its
# tenancy. The stack's tags reach every resource of it that takes tags.
tenancy="${POKERTOUR_TENANCY:-GA}"
tags=("project=pokertour" "tenancy=$tenancy")
account="$(aws sts get-caller-identity --query Account --output text)"
code_bucket="${stack}-code-${account}-${region}"
out="$root/deploy/out"
echo "deploy: stack $stack in $region of account $account"

if [[ "$build" == yes ]]; then
  bash "$root/scripts/build.sh" web
  echo "deploy: the functions' executable (docker/lambda.Dockerfile, linux/$arch)"
  rm -rf "$out/lambda"
  docker build --platform "linux/$arch" -f "$root/docker/lambda.Dockerfile" \
    --output "type=local,dest=$out/lambda" "$root"
fi
if [[ ! -x "$out/lambda/bootstrap" || ! -f "$root/pokertour_app/build/web/index.html" ]]; then
  echo "error: no build to deploy (deploy/out/lambda/bootstrap, pokertour_app/build/web)" >&2
  exit 1
fi
rm -f "$out/lambda.zip"
(cd "$out/lambda" && zip -qr "$out/lambda.zip" bootstrap models)
sum="$(shasum -a 256 "$out/lambda.zip" | cut -c1-16)"
code_key="lambda/$sum.zip"

if ! aws s3api head-bucket --bucket "$code_bucket" --region "$region" >/dev/null 2>&1; then
  echo "deploy: making the code bucket s3://$code_bucket"
  if [[ "$region" == us-east-1 ]]; then
    aws s3api create-bucket --bucket "$code_bucket" --region "$region" >/dev/null
  else
    aws s3api create-bucket --bucket "$code_bucket" --region "$region" \
      --create-bucket-configuration "LocationConstraint=$region" >/dev/null
  fi
  aws s3api put-public-access-block --bucket "$code_bucket" --region "$region" \
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
fi
aws s3api put-bucket-tagging --bucket "$code_bucket" --region "$region" \
  --tagging "TagSet=[{Key=project,Value=pokertour},{Key=tenancy,Value=$tenancy}]"
if ! aws s3api head-object --bucket "$code_bucket" --key "$code_key" --region "$region" >/dev/null 2>&1; then
  aws s3 cp --quiet "$out/lambda.zip" "s3://$code_bucket/$code_key" --region "$region"
fi
echo "deploy: code s3://$code_bucket/$code_key"

params=(
  "CodeBucket=$code_bucket"
  "CodeKey=$code_key"
  "GoogleClientId=${OIDC_CLIENT_ID:-}"
  "AityxUrl=$prod_url"
  "LambdaArchitecture=$arch"
)
[[ -n "${POKERTOUR_ALLOWED_DOMAINS:-}" ]] && params+=("AllowedDomains=$POKERTOUR_ALLOWED_DOMAINS")
[[ -n "${POKERTOUR_SCHEDULE_HOURS:-}" ]] && params+=("ScheduleHours=$POKERTOUR_SCHEDULE_HOURS")
[[ -n "${POKERTOUR_MAX_HANDS:-}" ]] && params+=("MaxHands=$POKERTOUR_MAX_HANDS")
[[ -n "${POKERTOUR_MAX_ENTRIES:-}" ]] && params+=("MaxEntries=$POKERTOUR_MAX_ENTRIES")
echo "deploy: the stack (a first deployment takes a few minutes: CloudFront)"
aws cloudformation deploy --region "$region" --stack-name "$stack" \
  --template-file "$root/deploy/template.yaml" \
  --capabilities CAPABILITY_NAMED_IAM --no-fail-on-empty-changeset \
  --parameter-overrides "${params[@]}" --tags "${tags[@]}"

output() {
  aws cloudformation describe-stacks --region "$region" --stack-name "$stack" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}
url="$(output Url)"
origin="$(output Origin)"
web_bucket="$(output WebBucket)"
data_bucket="$(output DataBucket)"
distribution="$(output DistributionId)"
leaderboard_key_object="pokertour/leaderboard.key"

echo "deploy: the web build to s3://$web_bucket/pokertour/"
aws s3 sync --quiet --delete --region "$region" "$root/pokertour_app/build/web" "s3://$web_bucket/pokertour/" \
  --exclude ".pokertour-services" --cache-control "public, max-age=300"
# The CLI doesn't know .wasm's type; CanvasKit needs it right.
aws s3 cp --quiet --recursive --region "$region" "s3://$web_bucket/pokertour/" "s3://$web_bucket/pokertour/" \
  --exclude "*" --include "*.wasm" --content-type application/wasm \
  --cache-control "public, max-age=300" --metadata-directive REPLACE
aws cloudfront create-invalidation --distribution-id "$distribution" --paths "/*" --query 'Invalidation.Id' --output text >/dev/null

# put_key <object> <value> <what>: writes the key, through a pipe, when
# --key or when the object is missing.
put_key() {
  local object="$1" value="$2" what="$3"
  if [[ "$upload_key" == no ]] && aws s3api head-object --bucket "$data_bucket" --key "$object" --region "$region" >/dev/null 2>&1; then
    return 0
  fi
  if [[ -z "$value" ]]; then
    echo "deploy: no $what key is set: s3://$data_bucket/$object is not written" >&2
    return 0
  fi
  printf '%s' "$value" | aws s3 cp --quiet --region "$region" - "s3://$data_bucket/$object"
  echo "deploy: the $what key is in s3://$data_bucket/$object"
}
put_key "$leaderboard_key_object" "${POKERTOUR_PROD_LEADERBOARD_KEY:-}" "production leaderboard (POKERTOUR_PROD_LEADERBOARD_KEY)"

cat <<MSG

Poker Tour is at $url

Production runs on $prod_url.

The Google OAuth client ${OIDC_CLIENT_ID:-(none: set POKERTOUR_OIDC_CLIENT_ID)} must list
  $origin
among its authorized JavaScript origins (Google Cloud, APIs & Services >
Credentials), or the sign-in button answers "origin not allowed".

Logs: aws logs tail /aws/lambda/$stack-runner --follow --region $region
A tournament now, from here: aws lambda invoke --function-name $stack-runner --invocation-type Event --payload '{"source":"cli"}' --region $region /dev/stdout
MSG
