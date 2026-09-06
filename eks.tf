module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "tracing-token-cluster"
  cluster_version = "1.31" # Modern, supported version

  # Allows your local terminal to securely communicate with the API Server
  cluster_endpoint_public_access = true
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    
    # Tier 2: System Nodes (CPU only)
    system = {
      name           = "system-node-group"
      instance_types = ["t3.large"]
      min_size       = 2
      max_size       = 3
      desired_size   = 2

      labels = {
        role = "system"
      }
    }

  # Tier 3: GPU Inference Nodes
    gpu_v2= {
      name           = "gpu-node-group"
      instance_types = ["g5.xlarge"]
      
      min_size       = 1
      max_size       = 2
      desired_size   = 1

      # This AMI comes pre-loaded with NVIDIA drivers by AWS
      ami_type = "AL2_x86_64_GPU"
# Explicit block device mapping to force 100GB root volume
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 100
            volume_type           = "gp3"
            delete_on_termination = true
          }
        }
      }

      labels = {
        workload = "gpu"
        role     = "inference"
      }

      # Prevents Prometheus/Istio/etc from stealing expensive GPU resources
      taints = {
        gpu = {
          key    = "nvidia.com/gpu"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }
}