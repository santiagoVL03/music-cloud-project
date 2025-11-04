output "k8s_master_public_ip" {
  description = "IP pública del nodo master de Kubernetes"
  value       = aws_instance.k8s_master.public_ip
}

output "k8s_master_private_ip" {
  description = "IP privada del nodo master de Kubernetes"
  value       = aws_instance.k8s_master.private_ip
}

output "k8s_worker_public_ips" {
  description = "IPs públicas de los nodos worker de Kubernetes"
  value       = aws_instance.k8s_worker[*].public_ip
}

output "k8s_worker_private_ips" {
  description = "IPs privadas de los nodos worker de Kubernetes"
  value       = aws_instance.k8s_worker[*].private_ip
}

output "ssh_command_master" {
  description = "Comando SSH para conectarse al master"
  value       = "ssh -i ${var.ssh_private_key_path} ubuntu@${aws_instance.k8s_master.public_ip}"
}

output "kubectl_get_nodes" {
  description = "Comando para verificar los nodos del cluster"
  value       = "ssh -i ${var.ssh_private_key_path} ubuntu@${aws_instance.k8s_master.public_ip} 'kubectl get nodes'"
}

output "application_url" {
  description = "URL de la aplicación (NodePort 30080)"
  value       = "http://${aws_instance.k8s_master.public_ip}:30080"
}
