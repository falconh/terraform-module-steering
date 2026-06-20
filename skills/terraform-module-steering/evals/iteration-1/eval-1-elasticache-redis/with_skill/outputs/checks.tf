################################################################################
# Cost guardrail: surface the Multi-AZ cost implication at plan/apply.
#
# Multi-AZ + automatic failover is hardcoded ON (HA, FSBP ElastiCache.3). That
# requires >= 2 nodes across AZs, which roughly doubles node-hour cost vs a
# single-node deployment, and adds cross-AZ data-transfer charges. A `check`
# block emits this as a WARNING during `terraform plan`/`apply` (a failed check
# assertion only warns in real runs) so consumers see it without it blocking.
#
# NOTE for `terraform test`: under the test harness a failed `check` is a RUN
# FAILURE (not a warning). Because Multi-AZ is ON by default this warning fires
# by default, so the test suite proves it via a dedicated run with
# `expect_failures = [check.multi_az_cost_warning]` (see tests/).
################################################################################

check "multi_az_cost_warning" {
  assert {
    condition = local.multi_az_enabled != true
    error_message = join(" ", [
      "COST WARNING: Multi-AZ with automatic failover is ENABLED (secure-by-default HA).",
      "This provisions ${var.num_cache_clusters} nodes across multiple AZs, which increases",
      "node-hour cost (roughly proportional to node count) and adds cross-AZ data-transfer",
      "charges versus a single-node cache. This is intentional and required for FSBP",
      "ElastiCache.3; budget accordingly."
    ])
  }
}
