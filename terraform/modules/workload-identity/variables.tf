variable "name" {
  description = "Prefix for the pool and provider ids"
  type        = string
}

variable "github_owner" {
  description = "GitHub user or org that owns the repository. The provider's attribute_condition pins to this — get it wrong and every workflow fails auth, leave it out and every repo on GitHub can authenticate."
  type        = string
}

variable "github_repo" {
  description = "Repository name only, without the owner prefix. The IAM binding is scoped to owner/repo."
  type        = string
}

variable "ci_service_account_id" {
  description = "Fully qualified id of the account CI impersonates (the iam module's ci_service_account_id output), not its email"
  type        = string
}
