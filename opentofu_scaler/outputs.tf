output "load_balancer_dns" {
  value       = aws_lb.web_lb.dns_name
  description = "URL del Load Balancer para probar"
}
