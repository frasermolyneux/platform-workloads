removed {
  from = github_repository.workload["portal-event-ingest"]

  lifecycle {
    destroy = false
  }
}

removed {
  from = github_repository.workload["portal-bots"]

  lifecycle {
    destroy = false
  }
}
