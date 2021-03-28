provider "hcloud" {
  token = var.hcloud_token
}

resource "hcloud_firewall" "kubernetes" {
  name = "${var.name}-fw"
  rule {
    direction  = "in"
    protocol   = "tcp"
    source_ips = ["0.0.0.0/0", "::/0"]
    port       = var.ssh_port
  }
  rule {
    direction  = "in"
    protocol   = "tcp"
    source_ips = ["0.0.0.0/0", "::/0"]
    port       = "6443"
  }
  rule {
    direction  = "in"
    protocol   = "udp"
    source_ips = ["0.0.0.0/0", "::/0"]
    port       = "6443"
  }
}

resource "hcloud_ssh_key" "k8s_admin" {
  name       = var.name
  public_key = file(var.ssh_public_key)
}

resource "hcloud_network" "kubenet" {
  name     = var.name
  ip_range = var.network_cidr
}

resource "hcloud_network_subnet" "kubenet" {
  network_id   = hcloud_network.kubenet.id
  type         = "server"
  network_zone = "eu-central"
  ip_range     = var.network_cidr
}

resource "hcloud_load_balancer" "kube_load_balancer" {
  name               = "${var.name}-lb"
  load_balancer_type = "lb11"
  location           = var.location
}

resource "hcloud_load_balancer_service" "kube_load_balancer_service" {
  load_balancer_id = hcloud_load_balancer.kube_load_balancer.id
  protocol         = "tcp"
  listen_port      = 6443
  destination_port = 6443
}

resource "hcloud_server" "master" {
  depends_on   = [hcloud_load_balancer.kube_load_balancer]
  count        = var.master_count
  name         = "${var.name}-master-${count.index + 1}"
  location     = var.location
  server_type  = var.master_type
  image        = var.master_image
  ssh_keys     = [hcloud_ssh_key.k8s_admin.id]
  firewall_ids = [hcloud_firewall.kubernetes.id]

  connection {
    host        = self.ipv4_address
    type        = "ssh"
    private_key = file(var.ssh_private_key)
  }

  provisioner "file" {
    source      = "${path.module}/scripts/bootstrap.sh"
    destination = "/root/bootstrap.sh"
  }

  provisioner "remote-exec" {
    inline = ["SSH_PORT=${var.ssh_port} bash /root/bootstrap.sh"]
  }
}

resource "hcloud_server" "node" {
  count       = var.node_count
  name        = "${var.name}-worker-${count.index + 1}"
  server_type = var.node_type
  image       = var.node_image
  location    = var.location
  depends_on  = [hcloud_server.master]
  ssh_keys    = [hcloud_ssh_key.k8s_admin.id]

  connection {
    host        = self.ipv4_address
    type        = "ssh"
    private_key = file(var.ssh_private_key)
  }

  provisioner "file" {
    source      = "${path.module}/scripts/bootstrap.sh"
    destination = "/root/bootstrap.sh"
  }

  provisioner "remote-exec" {
    inline = ["SSH_PORT=${var.ssh_port} bash /root/bootstrap.sh"]
  }
}

resource "hcloud_server_network" "master_network" {
  count      = var.master_count
  depends_on = [hcloud_server.master]
  server_id  = hcloud_server.master[count.index].id
  network_id = hcloud_network.kubenet.id
}

resource "hcloud_load_balancer_target" "load_balancer_target" {
  count            = var.master_count
  depends_on       = [hcloud_server.master]
  type             = "server"
  server_id        = hcloud_server.master[count.index].id
  load_balancer_id = hcloud_load_balancer.kube_load_balancer.id
}

resource "hcloud_server_network" "node_network" {
  count      = var.node_count
  depends_on = [hcloud_server.node]
  server_id  = hcloud_server.node[count.index].id
  network_id = hcloud_network.kubenet.id
}
