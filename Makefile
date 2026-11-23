TERRAFORM_DOCS_VERSION := 0.25.1

# Docs generation is pinned to a specific terraform-docs version and run via
# docker, so local runs and CI produce byte-identical README output. Bump
# TERRAFORM_DOCS_VERSION (and regenerate the README) to change the generator.
generate-doc:
	docker run --rm --user "$$(id -u):$$(id -g)" -v "$(CURDIR)":/src -w /src quay.io/terraform-docs/terraform-docs:$(TERRAFORM_DOCS_VERSION) markdown table --lockfile=false --output-file README.md --output-mode inject .
