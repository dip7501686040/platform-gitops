# cluster_name is intentionally left as "ai-notification-floci" rather than
# renamed to match this file — EKS cluster names are immutable in AWS
# (rename = destroy/recreate), and this pass already has a live cluster in
# envs/state/local.tfstate. Only the file/tag naming moved to local/prod;
# renaming provisioned resources is a separate, deliberate decision.
aws_region   = "us-east-1"
cluster_name = "ai-notification-floci"
k8s_version  = "1.31"

vpc_cidr           = "10.0.0.0/16"
az_count           = 2
single_nat_gateway = true

node_instance_types = ["t3.medium"]
node_desired_size   = 1
node_min_size       = 1
node_max_size       = 1

# Floci's EKS control-plane emulation doesn't provide a resolvable OIDC
# issuer, so the IRSA trust chain (aws_iam_openid_connect_provider's TLS
# cert lookup) can't be validated locally — keep addons off for this pass.
enable_irsa_addons = false

# Path A/B test in progress (see plan §0) — "ec2" until proven otherwise
# against Floci's EC2 emulation; switch to "docker" if nested Docker
# inside Floci's EC2-emulation container doesn't work.
jenkins_mode          = "ec2"
jenkins_instance_type = "t3.medium"
# Disposable local-only pass — open is fine here, never for the AWS env.
jenkins_admin_cidr = "0.0.0.0/0"

tags = {
  Project     = "ai-notification-system"
  Environment = "local"
  ManagedBy   = "terraform"
}
