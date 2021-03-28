output "node_ips" {
  value = [hcloud_server.node.*.ipv4_address]
}

output "master_ips" {
  value = [hcloud_server.master.*.ipv4_address]
}

output "network_id" {
  value = [hcloud_network.kubenet.id]
}

output "loadbalancer_ip" {
  value = hcloud_load_balancer.kube_load_balancer.ipv4
}
