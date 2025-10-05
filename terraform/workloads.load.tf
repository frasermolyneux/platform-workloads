locals {
  workload_json_files = [
    for file_path in try(fileset("${path.module}/workloads", "**/*.json"), []) :
    file_path
    if !startswith(file_path, "examples/")
  ]

  workloads_from_files = [
    for file_path in local.workload_json_files :
    jsondecode(file("${path.module}/workloads/${file_path}"))
  ]

  all_workloads = concat(var.workloads, local.workloads_from_files)
}
