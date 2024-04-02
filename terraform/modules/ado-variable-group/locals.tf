locals {
  tags = merge(var.tags, { Workload = var.workload_name, Environment = var.environment_name })
}
