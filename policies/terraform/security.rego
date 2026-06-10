package terraform.security

import rego.v1

deny contains msg if {
  resource := input.resource_changes[_]
  resource.type == "aws_iam_policy"

  policy := json.unmarshal(resource.change.after.policy)
  statement := policy.Statement[_]

  statement.Action == "*"

  msg := sprintf("IAM policy '%s' allows wildcard Action '*'", [resource.address])
}

deny contains msg if {
  resource := input.resource_changes[_]
  resource.type == "aws_iam_policy"

  policy := json.unmarshal(resource.change.after.policy)
  statement := policy.Statement[_]

  statement.Resource == "*"

  msg := sprintf("IAM policy '%s' allows wildcard Resource '*'", [resource.address])
}

deny contains msg if {
  resource := input.resource_changes[_]
  resource.type == "aws_s3_bucket_public_access_block"

  resource.change.after.block_public_acls == false
  resource.change.after.block_public_policy == false
  resource.change.after.ignore_public_acls == false
  resource.change.after.restrict_public_buckets == false

  msg := sprintf("S3 bucket public access block is disabled in '%s'", [resource.address])
}

deny contains msg if {
  resource := input.resource_changes[_]
  resource.type == "aws_security_group"

  ingress := resource.change.after.ingress[_]
  cidr := ingress.cidr_blocks[_]
  cidr == "0.0.0.0/0"

  msg := sprintf("Security group '%s' allows ingress from 0.0.0.0/0", [resource.address])
}