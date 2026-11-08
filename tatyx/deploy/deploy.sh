#!/usr/bin/env bash
# Deploys tatyx to AWS, serverless (deploy/template.yaml):
#   1. builds the app (scripts/build.sh: the web build under /tatyx/ and
#      the leaderboard's runner), and zips the functions' code: the
#      server (tatyx_server/*.mjs), the runner and the strategies kept in
#      the repository (strategies/), which start an empty tour
#   2. uploads the zip to a code bucket of this account and region
#      (<stack>-code-<account>-<region>, made on the first run)
#   3. creates or updates the CloudFormation stack: the data and web
#      buckets, CloudFront, the API and runner functions, the schedule
#   4. syncs the web build to the web bucket under tatyx/, and
#      invalidates CloudFront
#   5. puts the leaderboard's key, TATYX_PROD_LEADERBOARD_KEY, in the
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
# Settings, from the environment or .env: TATYX_OIDC_CLIENT_ID (the
# sign-in; without it nobody can sign in), AITYX_PROD_URL and
# TATYX_PROD_LEADERBOARD_KEY (production's aityx), TATYX_ALLOWED_DOMAINS,
# TATYX_SCHEDULE_HOURS, TATYX_MAX_ENTRIES; and TATYX_STACK (default
# tatyx), AWS_REGION (default the CLI's), LAMBDA_ARCH (arm64, the
# default, or x86_64). Needs the AWS CLI with credentials for the
# account, and zip.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../scripts/env.sh
source "$root/scripts/env.sh"
load_env TATYX_OIDC_CLIENT_ID AITYX_PROD_URL TATYX_PROD_LEADERBOARD_KEY TATYX_ALLOWED_DOMAINS TATYX_SCHEDULE_HOURS TATYX_MAX_ENTRIES

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

stack="${TATYX_STACK:-tatyx}"
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
account="$(aws sts get-caller-identity --query Account --output text)"
code_bucket="${stack}-code-${account}-${region}"
out="$root/deploy/out"
echo "deploy: stack $stack in $region of account $account"

if [[ "$build" == yes ]]; then
  bash "$root/scripts/build.sh"
fi
web="$root/tatyx_app/dist"
if [[ ! -f "$web/index.html" || ! -f "$root/tatyx_app/dist-runner/runner.mjs" ]]; then
  echo "error: no build to deploy (tatyx_app/dist, tatyx_app/dist-runner)" >&2
  exit 1
fi
if [[ "$(cat "$web/.tatyx-services" 2>/dev/null)" != 'base=/tatyx/' ]]; then
  echo "error: tatyx_app/dist is not built for /tatyx/: run scripts/build.sh" >&2
  exit 1
fi

# The functions' code: the server, the runner, the strategies; no tests, no keys.
rm -rf "$out/lambda" "$out/lambda.zip"
mkdir -p "$out/lambda/tatyx_server" "$out/lambda/tatyx_app/dist-runner" "$out/lambda/strategies"
cp "$root"/tatyx_server/*.mjs "$out/lambda/tatyx_server/"
cp "$root/tatyx_app/dist-runner/runner.mjs" "$out/lambda/tatyx_app/dist-runner/"
cp "$root"/strategies/*.json "$out/lambda/strategies/" 2>/dev/null || true
(cd "$out/lambda" && zip -qrX "$out/lambda.zip" .)
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
if ! aws s3api head-object --bucket "$code_bucket" --key "$code_key" --region "$region" >/dev/null 2>&1; then
  aws s3 cp --quiet "$out/lambda.zip" "s3://$code_bucket/$code_key" --region "$region"
fi
echo "deploy: code s3://$code_bucket/$code_key"

params=(
  "CodeBucket=$code_bucket"
  "CodeKey=$code_key"
  "GoogleClientId=${TATYX_OIDC_CLIENT_ID:-}"
  "AityxUrl=$prod_url"
  "LambdaArchitecture=$arch"
)
[[ -n "${TATYX_ALLOWED_DOMAINS:-}" ]] && params+=("AllowedDomains=$TATYX_ALLOWED_DOMAINS")
[[ -n "${TATYX_SCHEDULE_HOURS:-}" ]] && params+=("ScheduleHours=$TATYX_SCHEDULE_HOURS")
[[ -n "${TATYX_MAX_ENTRIES:-}" ]] && params+=("MaxEntries=$TATYX_MAX_ENTRIES")
echo "deploy: the stack (a first deployment takes a few minutes: CloudFront)"
aws cloudformation deploy --region "$region" --stack-name "$stack" \
  --template-file "$root/deploy/template.yaml" \
  --capabilities CAPABILITY_NAMED_IAM --no-fail-on-empty-changeset \
  --parameter-overrides "${params[@]}"

output() {
  aws cloudformation describe-stacks --region "$region" --stack-name "$stack" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}
url="$(output Url)"
origin="$(output Origin)"
web_bucket="$(output WebBucket)"
data_bucket="$(output DataBucket)"
distribution="$(output DistributionId)"
leaderboard_key_object="tatyx/leaderboard.key"

# Vite's hashed assets never change; the page, the portraits and the rest are checked again.
echo "deploy: the web build to s3://$web_bucket/tatyx/"
aws s3 sync --quiet --delete --region "$region" "$web" "s3://$web_bucket/tatyx/" \
  --exclude ".tatyx-services" --exclude "assets/*" --cache-control "no-cache"
aws s3 sync --quiet --region "$region" "$web/assets" "s3://$web_bucket/tatyx/assets/" \
  --cache-control "public, max-age=31536000, immutable"
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
  printf '%s' "$value" | aws s3 cp --quiet --region "$region" --sse AES256 - "s3://$data_bucket/$object"
  echo "deploy: the $what key is in s3://$data_bucket/$object"
}
put_key "$leaderboard_key_object" "${TATYX_PROD_LEADERBOARD_KEY:-}" "production leaderboard (TATYX_PROD_LEADERBOARD_KEY)"

cat <<MSG

tatyx is at $url

Production runs on $prod_url.

The Google OAuth client ${TATYX_OIDC_CLIENT_ID:-(none: set TATYX_OIDC_CLIENT_ID)} must list
  $origin
among its authorized JavaScript origins (Google Cloud, APIs & Services >
Credentials), or the sign-in button answers "origin not allowed".

Logs: aws logs tail /aws/lambda/$stack-runner --follow --region $region
A tournament now, from here: aws lambda invoke --function-name $stack-runner --invocation-type Event --payload '{"source":"cli"}' --cli-binary-format raw-in-base64-out --region $region /dev/stdout
MSG
