# How to Use AWS CloudFormation

AWS CloudFormation lets you define and provision infrastructure as code (IaC). Instead of clicking through the AWS Console, you write a YAML (or JSON) **template** and CloudFormation creates, updates, or deletes your resources automatically.

---

## Core Concepts

| Concept | What it is |
|---|---|
| **Template** | YAML/JSON file describing your AWS resources |
| **Stack** | A running instance of a template (the actual resources) |
| **Parameters** | Input values you pass at deploy time |
| **Resources** | The AWS services you're provisioning (EC2, S3, IAM…) |
| **Outputs** | Values the stack exposes after creation (IP address, ARN…) |
| **Exports / Imports** | Cross-stack references (`Fn::ImportValue`) |

---

## Template Structure

Every CloudFormation template follows this skeleton:

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: What this stack does

Parameters:         # optional – inputs at deploy time
  MyParam:
    Type: String
    Default: hello

Resources:          # required – the actual AWS resources
  MyBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Ref MyParam

Outputs:            # optional – expose values after creation
  BucketName:
    Value: !Ref MyBucket
```

---

## Intrinsic Functions (the building blocks)

| Function | Usage | Example |
|---|---|---|
| `!Ref` | Reference a parameter or resource | `!Ref InstanceType` |
| `!Sub` | String interpolation | `!Sub "${EnvironmentName}-vpc"` |
| `!GetAtt` | Get an attribute of a resource | `!GetAtt AppInstance.PublicIp` |
| `Fn::ImportValue` | Import an Output from another stack | `Fn::ImportValue: !Sub "${Env}-vpc-id"` |
| `Fn::Base64` | Encode a string (used for EC2 UserData) | `Fn::Base64: !Sub \|` |

---

## How Stacks Are Deployed in This Project

### Step 1 — Deploy the VPC stack first

The VPC stack (`vpc.yaml`) creates the network and **exports** subnet and VPC IDs that the app stack imports.

```bash
aws cloudformation deploy \
  --template-file CloudFormation/vpc.yaml \
  --stack-name databite-vpc \
  --parameter-overrides EnvironmentName=databite
```

### Step 2 — Upload the app code to S3

```bash
aws s3 cp DataBite/backend/main.py s3://<your-bucket>/backend/main.py
```

### Step 3 — Deploy the app stack

Use the provided helper script:

```bash
./CloudFormation/deploy.sh <app-bucket> [stack-name] [key-name] [env-name]

# Example:
./CloudFormation/deploy.sh my-databite-bucket databite-app databite-key databite
```

What `deploy.sh` does internally:
1. Uploads `main.py` to S3
2. Runs `aws cloudformation deploy` with `app.yaml`
3. Prints the stack Outputs (Public IP, App URL, API docs URL)

---

## Understanding `app.yaml`

```
Parameters → EnvironmentName, InstanceType, KeyName, AmiId, AppBucket, AppScriptKey
             ↓
Resources  → IAM Role + Instance Profile  (grants EC2 access to S3)
           → Security Group               (allows port 80 + 22)
           → EC2 Instance                 (runs Nginx + FastAPI via UserData)
             ↓
Outputs    → InstanceId, PublicIP, AppURL, ApiDocsURL
```

Key patterns in `app.yaml`:

**SSM Parameter for latest AMI** — always gets the newest Amazon Linux 2023:
```yaml
AmiId:
  Type: AWS::SSM::Parameter::Value<AWS::EC2::Image::Id>
  Default: /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64
```

**Cross-stack import** — the VPC and subnet come from the VPC stack:
```yaml
VpcId:
  Fn::ImportValue: !Sub ${EnvironmentName}-vpc-id
SubnetId:
  Fn::ImportValue: !Sub ${EnvironmentName}-public-subnet-1
```

**UserData** — bootstraps the EC2 instance on first boot (installs Python, Nginx, pulls `main.py` from S3, configures systemd):
```yaml
UserData:
  Fn::Base64: !Sub |
    #!/bin/bash
    set -e
    dnf install -y python3.11 nginx
    aws s3 cp s3://${AppBucket}/${AppScriptKey} /opt/databite/backend/main.py
    ...
```

---

## Common AWS CLI Commands

```bash
# Deploy (create or update) a stack
aws cloudformation deploy \
  --template-file template.yaml \
  --stack-name my-stack \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides Key=Value

# List all stacks
aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE

# Describe a stack and its outputs
aws cloudformation describe-stacks --stack-name my-stack --query "Stacks[0].Outputs"

# See events (useful for debugging failures)
aws cloudformation describe-stack-events --stack-name my-stack

# Delete a stack (destroys all resources)
aws cloudformation delete-stack --stack-name my-stack

# Validate a template before deploying
aws cloudformation validate-template --template-body file://template.yaml
```

---

## The CAPABILITY_NAMED_IAM Flag

When your template creates or modifies IAM resources (roles, policies, instance profiles), CloudFormation requires you to explicitly acknowledge this:

```bash
--capabilities CAPABILITY_NAMED_IAM   # when you set a custom RoleName/PolicyName
--capabilities CAPABILITY_IAM         # when names are auto-generated
```

`app.yaml` uses `CAPABILITY_NAMED_IAM` because `AppInstanceRole` has a custom `RoleName`.

---

## Stack Updates vs. Replacements

CloudFormation can **update** most resource properties in place. But some changes (e.g., changing an EC2 `ImageId` or `KeyName`) require the resource to be **replaced** — CloudFormation deletes and recreates it. Check the [CloudFormation resource documentation](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-template-resource-type-ref.html) for **Update requires: Replacement** warnings.

---

## Debugging Failures

1. Check the **Events** tab in the CloudFormation Console (or `describe-stack-events` via CLI)
2. Look for `CREATE_FAILED` events — they include the error message
3. For UserData issues, SSH into the EC2 instance and check:
   ```bash
   cat /var/log/cloud-init-output.log
   ```

---

## Files in This Project

| File | Purpose |
|---|---|
| [vpc.yaml](vpc.yaml) | VPC, subnets, IGW, NAT Gateway — must be deployed first |
| [app.yaml](app.yaml) | EC2 instance with IAM role, security group, UserData bootstrap |
| [s3-ec2-app.yaml](s3-ec2-app.yaml) | Alternative app stack variant |
| [cloudfront-app.yaml](cloudfront-app.yaml) | CloudFront distribution in front of the app |
| [deploy.sh](deploy.sh) | Helper script: uploads code to S3 then deploys `app.yaml` |
| [frontend/](frontend/) | Frontend static assets |
