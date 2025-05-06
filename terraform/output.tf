
output "cluster_name" {
  value = aws_eks_cluster.eks_cluster.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.eks_cluster.endpoint
}

output "service_loadbalancer_dns" {
  value = kubernetes_service.webapp.status[0].load_balancer[0].ingress[0].hostname
  description = "The DNS name of the LoadBalancer"
}