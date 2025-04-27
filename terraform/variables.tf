variable "region" {
  default = "ap-south-1"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
  type    = string
}

variable "cluster" {
  default = "glps-eks-cluster"
  type    = string
}

variable "public_subnet_cidrs" {
  default = [ "10.0.1.0/24", "10.0.3.0/24" ]
}

variable "private_subnet_cidrs" { 
  default = [ "10.0.5.0/24", "10.0.7.0/24" ]
}

variable "web_image" {
  description = "Docker image for the static web app1"
  type = string
}

