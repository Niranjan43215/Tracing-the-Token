# 🚀 Tracing the Token: EKS GPU Infrastructure & LLM Observability Pipeline

A production-grade Infrastructure as Code (IaC) and full-stack Observability pipeline for serving Large Language Models (LLMs) on AWS EKS using **vLLM**, **NVIDIA DCGM Exporter**, **Prometheus**, and **Grafana**.

---

## 📌 Project Overview & Achievements

This project automates the end-to-end provisioning of a GPU-enabled Kubernetes cluster on AWS and configures deep, multi-layered observability (hardware GPU telemetry + application token metrics).

### Key Achievements:
1. **Automated AWS Cloud Infrastructure**: Provisioned VPC networking and an EKS cluster with segregated system and GPU worker node groups using Terraform.
2. **GPU LLM Inference Serving**: Deployed vLLM (serving `Qwen/Qwen2.5-0.5B-Instruct`) with dedicated GPU taints, tolerations, and resource limits.
3. **Hardware-Level GPU Telemetry**: Deployed NVIDIA DCGM Exporter as a DaemonSet to stream GPU utilization, VRAM usage, temperature, power, and memory metrics.
4. **LLM Token-Level Observability**: Configured Prometheus ServiceMonitors to track token throughput (tokens/sec), Time-To-First-Token (TTFT), Inter-Token-Latency (ITL), and KV-Cache usage.
5. **Dynamic Prometheus & Grafana Integration**: Custom-tuned `kube-prometheus-stack` Helm values to automatically discover ServiceMonitors across cluster namespaces.

---

## 🏗️ Architecture Diagram

```
                         +-----------------------------------------------+
                         |               AWS Cloud VPC                   |
                         |               (10.0.0.0/16)                   |
                         +-----------------------+-----------------------+
                                                 |
                         +-----------------------v-----------------------+
                         |             Amazon EKS Cluster                |
                         +-----------------------+-----------------------+
                                                 |
         +---------------------------------------+---------------------------------------+
         |                                                                               |
         v                                                                               v
+-------------------------------+                               +-------------------------------+
|       System Node Group       |                               |       GPU Inference Group     |
|          (t3.large)           |                               |         (g5.xlarge GPU)       |
+-------------------------------+                               +-------------------------------+
| • kube-prometheus-stack       |                               | • vLLM Server (Qwen2.5-0.5B)  |
| • Prometheus Operator         |                               | • NVIDIA DCGM Exporter        |
| • Grafana Dashboards          |                               |   (DaemonSet on port 9400)    |
+---------------+---------------+                               +---------------+---------------+
                ^                                                               ^
                |                                                               |
                +================ Scrapes via ServiceMonitors ==================+
```

---

## 🎯 Point-by-Point Technical Implementation

### 1. Infrastructure as Code (Terraform)
* **VPC Networking ([`vpc.tf`](file:///c:/Users/niran/Desktop/tracing-the-token/vpc.tf))**:
  * Dual-AZ network design (`us-east-1a`, `us-east-1b`) with 2 private subnets (`10.0.1.0/24`, `10.0.2.0/24`) and 2 public subnets (`10.0.101.0/24`, `10.0.102.0/24`).
  * Managed NAT Gateway for private node egress.
  * Tagged for AWS ALB integration (`kubernetes.io/role/elb`, `kubernetes.io/role/internal-elb`).
* **EKS Cluster & Node Pools ([`eks.tf`](file:///c:/Users/niran/Desktop/tracing-the-token/eks.tf))**:
  * EKS Cluster version `1.31`.
  * **System Node Group**: `t3.large` (2-3 nodes) for Prometheus, Grafana, and cluster services.
  * **GPU Inference Node Group**: `g5.xlarge` instances with AL2 GPU AMI (`AL2_x86_64_GPU`), 100GB `gp3` root volume for model storage.
  * Tainted with `nvidia.com/gpu=true:NoSchedule` and labeled `workload=gpu` to ensure only GPU pods run on GPU instances.
* **Provider Locking ([`providers.tf`](file:///c:/Users/niran/Desktop/tracing-the-token/providers.tf), [`.terraform.lock.hcl`](file:///c:/Users/niran/Desktop/tracing-the-token/.terraform.lock.hcl))**:
  * Pinned `aws` provider (`~> 5.0`) and Terraform version (`>= 1.3.0`).

---

### 2. LLM Serving with vLLM ([`vllm.yaml`](file:///c:/Users/niran/Desktop/tracing-the-token/vllm.yaml))
* **Container Image**: `vllm/vllm-openai:latest` providing OpenAI-compatible `/v1/completions` and `/v1/chat/completions` API endpoints.
* **Model Config**: Runs `Qwen/Qwen2.5-0.5B-Instruct` with `--gpu-memory-utilization 0.8`.
* **Resource Allocation**: Allocated 1 NVIDIA GPU (`nvidia.com/gpu: "1"`).
* **Targeting**: Matched `nodeSelector: workload: gpu` and tolerations for the GPU node taint.
* **Service**: Exposes port `8000` with named TCP port `http` for Prometheus scraping.

---

### 3. GPU & Application Observability Pipeline
* **NVIDIA DCGM Exporter ([`dcgm-exporter.yaml`](file:///c:/Users/niran/Desktop/tracing-the-token/dcgm-exporter.yaml))**:
  * Runs as a `DaemonSet` using `nvcr.io/nvidia/k8s/dcgm-exporter:4.6.0-4.8.3-distroless`.
  * Exposes port `9400` for hardware metrics (temperature, power, VRAM, GPU usage, profiling).
  * Mounts host Path `/var/lib/kubelet/pod-resources` to map GPU metrics directly to individual pod names.
  * Added `SYS_ADMIN` capability for low-level GPU profiling.
* **DCGM ServiceMonitor ([`dcgm-service-monitor.yaml`](file:///c:/Users/niran/Desktop/tracing-the-token/dcgm-service-monitor.yaml))**:
  * Targets `dcgm-exporter` services in namespace `monitoring` at 15s scrape intervals.
* **vLLM ServiceMonitor ([`vllm-servicemonitor.yaml`](file:///c:/Users/niran/Desktop/tracing-the-token/vllm-servicemonitor.yaml))**:
  * Targets `vllm-service` in `default` namespace on port `http` (`/metrics`) at 15s scrape intervals.
  * Captures token-level metrics: throughput, TTFT latency, request count, and KV-cache saturation.
* **Prometheus & Grafana Tuning ([`prometheus-values.yaml`](file:///c:/Users/niran/Desktop/tracing-the-token/prometheus-values.yaml))**:
  * Set `serviceMonitorSelectorNilUsesHelmValues: false` so Prometheus dynamically picks up ServiceMonitors from all namespaces regardless of release labels.

---

## 🛠️ How to Deploy & Use This Project

### Prerequisites
* [Terraform](https://www.terraform.io/) >= 1.3.0
* [AWS CLI](https://aws.amazon.com/cli/) configured with administrative access
* [kubectl](https://kubernetes.io/docs/tasks/tools/) and [Helm](https://helm.sh/)

### Step 1: Provision Infrastructure with Terraform
```bash
# Initialize and apply Terraform
terraform init
terraform apply -auto-approve

# Configure kubectl context for EKS
aws eks update-kubeconfig --region us-east-1 --name tracing-token-cluster
```

### Step 2: Deploy Prometheus & Grafana Monitoring Stack
```bash
# Add prometheus-community Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Create monitoring namespace and install kube-prometheus-stack with custom values
kubectl create namespace monitoring
helm install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f prometheus-values.yaml
```

### Step 3: Deploy NVIDIA DCGM Exporter & ServiceMonitors
```bash
# Apply DCGM Exporter DaemonSet
kubectl apply -f dcgm-exporter.yaml

# Apply ServiceMonitors for DCGM and vLLM
kubectl apply -f dcgm-service-monitor.yaml
kubectl apply -f vllm-servicemonitor.yaml
```

### Step 4: Deploy vLLM Inference Server
```bash
# Deploy vLLM deployment & service
kubectl apply -f vllm.yaml

# Verify pod status on GPU node
kubectl get pods -w
```

### Step 5: Access Monitoring Dashboards
```bash
# Port-forward Grafana UI
kubectl port-forward svc/monitoring-grafana 3000:80 -n monitoring
```
* Open browser at `http://localhost:3000` (Default login: `admin` / `prom-operator`).
* Import GPU dashboards to visualize DCGM metrics and vLLM token throughput!

---

## 📁 Repository Structure

```
tracing-the-token/
├── eks.tf                       # EKS cluster and node group definitions
├── vpc.tf                       # VPC networking and subnet configuration
├── providers.tf                 # Terraform provider requirements
├── .terraform.lock.hcl          # Provider lock file
├── vllm.yaml                    # vLLM inference server Deployment & Service
├── dcgm-exporter.yaml           # NVIDIA DCGM Exporter DaemonSet & Service
├── dcgm-service-monitor.yaml    # ServiceMonitor for DCGM Exporter
├── vllm-servicemonitor.yaml     # ServiceMonitor for vLLM metrics
├── prometheus-values.yaml       # Helm configuration for kube-prometheus-stack
├── .gitignore                   # Ignores terraform state and binary caches
└── README.md                    # Detailed project documentation
```
