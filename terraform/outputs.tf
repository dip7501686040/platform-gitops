output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "oidc_issuer_url" {
  value = module.eks.oidc_provider_url
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}

output "ebs_csi_role_arn" {
  value = module.addons.ebs_csi_role_arn
}

output "lb_controller_role_arn" {
  value = module.addons.lb_controller_role_arn
}

output "jenkins_public_ip" {
  value = var.jenkins_mode == "ec2" ? module.jenkins_ec2[0].public_ip : null
}

output "jenkins_ssh_key_path" {
  value = var.jenkins_mode == "ec2" ? module.jenkins_ec2[0].ssh_private_key_path : null
}

output "jenkins_ssh_command" {
  value = var.jenkins_mode == "ec2" ? "ssh -i ${module.jenkins_ec2[0].ssh_private_key_path} ec2-user@${module.jenkins_ec2[0].public_ip}" : null
}

output "jenkins_admin_password_path" {
  value = var.jenkins_mode == "ec2" ? module.jenkins_ec2[0].admin_password_path : null
}
