module "http_ingress" {
  source = "./modules/http-ingress"
}

output "http_ingress_catalog" {
  description = "Versioned non-secret HTTP ingress inventory and target intent; publication does not activate target settings."
  value       = module.http_ingress.catalog
}

output "http_ingress_target" {
  description = "Target hostname, canonical status and exact private DNS projections; not an activation instruction."
  value       = module.http_ingress.target
}
