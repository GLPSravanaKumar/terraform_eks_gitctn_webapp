# 🚀 Terraform EKS Cluster with Web App Deployment

This project sets up an **Amazon EKS (Elastic Kubernetes Service)** cluster using **Terraform** and deploys a sample **web application** on it using the **Kubernetes provider**. It includes the following:

- VPC with public and private subnets
- NAT Gateway and Internet Gateway
- EKS Cluster and Node Group
- IAM roles for EKS and worker nodes
- Kubernetes Namespace, Deployment, and LoadBalancer Service


## 📁 Project Structure

.
├── main.tf                 # All main Terraform resources
├── variables.tf            # Input variables
├── outputs.tf              # Output values
├── providers.tf            # AWS and Kubernetes providers
└── README.md               # Project documentation


## ⚙️ Prerequisites

- AWS CLI configured (`aws configure`)
- Terraform installed (`v1.3+`)
- kubectl installed
- IAM user with required EKS/VPC permissions

## 🔧 How to Use

### 1. Clone this repository


git clone https://github.com/your-username/eks-terraform-project.git
cd eks-terraform-project

### 2. Update the `variables.tf` file

Modify the values such as:

- `cluster` – Name of your EKS cluster
- `vpc_cidr`, `public_subnet_cidrs`, `private_subnet_cidrs`
- `web_image` – Docker image for your web app (e.g., `nginx` or custom ECR image)

### 3. Initialize Terraform

terraform init

### 4. Apply Terraform Plan

terraform apply

Confirm when prompted with `yes`.

### 5. Update kubeconfig

Once the EKS cluster is created:

aws eks update-kubeconfig --region <your-region> --name <your-cluster-name>

Example:

aws eks update-kubeconfig --region ap-south-1 --name my-eks-cluster

### 6. Verify the Deployment


kubectl get all -n glps-ns


You should see the pods, service, and deployment.



## 🌐 Accessing the Web App

Once the `kubernetes_service` is provisioned with `type = LoadBalancer`, Terraform will create an AWS ELB.

To find the public URL:


kubectl get svc -n glps-ns


Use the **EXTERNAL-IP** to access the app in your browser.



## 🧹 Cleanup

To delete all resources:


terraform destroy

## 📌 Notes

- The `kubernetes` resources (deployment/service) are managed by Terraform after the cluster is provisioned.
- Ensure that your Kubernetes provider in `providers.tf` is properly set up with the correct EKS kubeconfig context.