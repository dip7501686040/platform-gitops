# Manages the Floci emulator container itself, not just the resources
# inside it — so a fresh `terraform apply` after `docker rm`-ing everything
# (including this container) pulls the image if it's missing and starts it,
# with no manual `docker run` step. Everything else in the AWS-provider
# graph depends_on this module so it isn't reachable via localhost:4566
# before Floci is actually listening.

resource "docker_image" "floci" {
  name         = var.image
  keep_locally = true # don't re-pull on every destroy/apply cycle
}

resource "docker_container" "floci" {
  name  = var.container_name
  image = docker_image.floci.image_id

  ports {
    internal = 4566
    external = var.port
  }

  # Floci shells out to the host Docker daemon to emulate EC2/ECR/EKS as
  # real containers — same requirement as the manual `docker run ... -v
  # /var/run/docker.sock:/var/run/docker.sock` invocation.
  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
  }

  # Not --rm: this container is now Terraform-managed state, meant to
  # survive between applies (and restart with the host/Docker daemon).
  restart  = "unless-stopped"
  must_run = true
}

# docker_container reports "running" as soon as the process starts, not once
# the API is actually accepting connections — a real gap on first boot.
# Block here so every dependent module's first API call doesn't race it.
resource "terraform_data" "wait_for_floci" {
  depends_on = [docker_container.floci]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      for i in $(seq 1 30); do
        if (exec 3<>/dev/tcp/127.0.0.1/${var.port}) 2>/dev/null; then
          exec 3<&- 3>&-
          echo "floci is accepting connections on port ${var.port}"
          exit 0
        fi
        sleep 2
      done
      echo "floci did not open port ${var.port} within 60s" >&2
      exit 1
    EOT
  }
}
