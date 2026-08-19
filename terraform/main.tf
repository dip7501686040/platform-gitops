# Started/pulled before anything else touches the aws provider — see
# module.floci's own depends_on chain (docker_container -> wait_for_floci).
# count-based (not a plain resource block) so real-AWS applies (manage_floci
# = false) never require the docker provider to be reachable at all.
module "floci" {
  count  = var.manage_floci ? 1 : 0
  source = "./modules/floci"
}

module "network" {
  source     = "./modules/network"
  depends_on = [module.floci]

  cluster_name       = var.cluster_name
  vpc_cidr           = var.vpc_cidr
  az_count           = var.az_count
  single_nat_gateway = var.single_nat_gateway
  tags               = var.tags
}

module "ecr" {
  source     = "./modules/ecr"
  depends_on = [module.floci]

  repository_names = var.ecr_repository_names
  tags             = var.tags
}

module "eks" {
  source     = "./modules/eks"
  depends_on = [module.floci]

  cluster_name        = var.cluster_name
  k8s_version         = var.k8s_version
  private_subnet_ids  = module.network.private_subnet_ids
  public_subnet_ids   = module.network.public_subnet_ids
  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  enable_irsa_addons  = var.enable_irsa_addons
  tags                = var.tags
}

module "addons" {
  source     = "./modules/addons"
  depends_on = [module.floci]

  enable_irsa_addons = var.enable_irsa_addons
  cluster_name       = var.cluster_name
  oidc_provider_arn  = module.eks.oidc_provider_arn
  oidc_provider_url  = module.eks.oidc_provider_url
  tags               = var.tags
}

module "jenkins_ec2" {
  count      = var.jenkins_mode == "ec2" ? 1 : 0
  source     = "./modules/jenkins-ec2"
  depends_on = [module.floci]

  instance_type        = var.jenkins_instance_type
  admin_cidr           = var.jenkins_admin_cidr
  vpc_id               = module.network.vpc_id
  subnet_id            = module.network.public_subnet_ids[0]
  github_push_username = var.github_push_username
  github_push_token    = var.github_push_token
  service_names        = var.ecr_repository_names
  tags                 = var.tags
}

# Browser access to the Jenkins UI from this Mac, without re-running any
# manual port-forward by hand after every apply. An SSH local-forward
# rather than relying on how Floci happens to publish container ports —
# works the same way against real AWS too (jenkins_admin_cidr there is
# meant to stay locked down, so a tunnel through the already-open SSH port
# is the point, not a workaround). Opt-in via jenkins_local_tunnel_port so
# a plain `terraform apply` on a CI box never tries to spawn one.
resource "terraform_data" "jenkins_ssh_tunnel" {
  count = (var.jenkins_mode == "ec2" && var.jenkins_local_tunnel_port > 0) ? 1 : 0

  # Any change here tears down the old tunnel (destroy provisioner) and
  # opens a fresh one (create provisioner) — covers instance replacement
  # (new IP) and simply changing the desired local port.
  triggers_replace = {
    public_ip  = module.jenkins_ec2[0].public_ip
    local_port = var.jenkins_local_tunnel_port
    key_path   = module.jenkins_ec2[0].ssh_private_key_path
    # public_ip alone isn't enough to detect a replaced instance: Floci
    # always reports 127.0.0.1 regardless of which underlying container it
    # is, so without instance_id here a replaced instance (new container,
    # new Floci-assigned SSH port) silently leaves the tunnel pointed at
    # the old, now-gone port.
    instance_id = module.jenkins_ec2[0].instance_id
    # Bump this whenever the provisioner script body below changes —
    # terraform_data only re-runs provisioners on replace, and replacement
    # is driven solely by this map, not by the script text itself.
    script_version = 3
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      PIDFILE="${path.root}/envs/state/jenkins-tunnel-${var.jenkins_local_tunnel_port}.pid"
      HOST="${module.jenkins_ec2[0].public_ip}"
      KEY="${module.jenkins_ec2[0].ssh_private_key_path}"
      SSH_PORT=22
      SSH_USER=ec2-user

      %{if var.manage_floci}
      # Floci's EC2 emulation is a plain amazonlinux:2023 container, not the
      # real AMI's cloud-init — there's no ec2-user account at all, only
      # root, which is who the generated key pair actually gets authorized
      # for (confirmed via `docker exec ... cat /root/.ssh/authorized_keys`).
      SSH_USER=root
      CONTAINER="floci-ec2-${module.jenkins_ec2[0].instance_id}"
      for i in $(seq 1 30); do
        MAPPED=$(docker port "$CONTAINER" 22 2>/dev/null | head -1)
        if [ -n "$MAPPED" ]; then
          SSH_PORT="$${MAPPED##*:}"
          break
        fi
        sleep 2
      done
      %{endif}

      SSH_OPTS="-i $KEY -p $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

      if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        kill "$(cat "$PIDFILE")" 2>/dev/null || true
        sleep 1
      fi

      echo "waiting for sshd on $HOST:$SSH_PORT..."
      for i in $(seq 1 60); do
        if ssh $SSH_OPTS -o ConnectTimeout=3 -o BatchMode=yes "$SSH_USER@$HOST" true 2>/dev/null; then
          break
        fi
        sleep 2
      done

      nohup ssh $SSH_OPTS -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -N \
        -L ${var.jenkins_local_tunnel_port}:localhost:8080 "$SSH_USER@$HOST" \
        >/dev/null 2>&1 &
      echo $! > "$PIDFILE"

      echo "Jenkins UI: http://localhost:${var.jenkins_local_tunnel_port}"
    EOT
  }


  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      PIDFILE="${path.root}/envs/state/jenkins-tunnel-${self.triggers_replace.local_port}.pid"
      if [ -f "$PIDFILE" ]; then
        kill "$(cat "$PIDFILE")" 2>/dev/null || true
        rm -f "$PIDFILE"
      fi
    EOT
  }

  depends_on = [module.jenkins_ec2]
}
