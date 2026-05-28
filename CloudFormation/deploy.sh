#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Usage: ./deploy.sh <app-bucket> [stack-name] [key-name] [env-name]
# ---------------------------------------------------------------------------
APP_BUCKET="${1:?Usage: $0 <app-bucket> [stack-name] [key-name] [env-name]}"
STACK_NAME="${2:-databite-app}"
KEY_NAME="${3:-databite-key}"
ENV_NAME="${4:-databite}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MAIN_PY="${SCRIPT_DIR}/../DataBite/backend/main.py"
S3_KEY="backend/main.py"

echo "==> Uploading main.py to s3://${APP_BUCKET}/${S3_KEY}"
aws s3 cp "${MAIN_PY}" "s3://${APP_BUCKET}/${S3_KEY}"

STACK_STATUS=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --query "Stacks[0].StackStatus" \
  --output text 2>/dev/null || echo "DOES_NOT_EXIST")

if [ "${STACK_STATUS}" = "ROLLBACK_COMPLETE" ]; then
  echo "==> Stack is in ROLLBACK_COMPLETE state — deleting before redeploy"
  aws cloudformation delete-stack --stack-name "${STACK_NAME}"
  aws cloudformation wait stack-delete-complete --stack-name "${STACK_NAME}"
  echo "==> Stack deleted"
fi

echo "==> Deploying CloudFormation stack: ${STACK_NAME}"
aws cloudformation deploy \
  --template-file "${SCRIPT_DIR}/cloudfront-app.yaml" \
  --stack-name "${STACK_NAME}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
      EnvironmentName="${ENV_NAME}" \
      KeyName="${KEY_NAME}" \
      AppBucket="${APP_BUCKET}" \
      AppScriptKey="${S3_KEY}"

echo "==> Uploading frontend to S3"
FRONTEND_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --query "Stacks[0].Outputs[?OutputKey=='S3BucketName'].OutputValue" \
  --output text)
aws s3 cp "${SCRIPT_DIR}/frontend/index.html" "s3://${FRONTEND_BUCKET}/index.html" --content-type text/html
echo "==> Frontend uploaded to s3://${FRONTEND_BUCKET}/index.html"

echo "==> Stack outputs:"
aws cloudformation describe-stacks \
  --stack-name "${STACK_NAME}" \
  --query "Stacks[0].Outputs" \
  --output table
