# Task runner for the keller.io infrastructure repo.
# Requires: opentofu, talosctl, sops, age (provided by the nix dev shell — `nix develop`).
# Recipes wrap the kellerIO OpenTofu environment; see tofu/talos-cluster/envs/kellerIO/justfile
# for env-local recipes (secrets-edit, destroy, ...).

set shell := ["bash", "-cu"]

# Path to the active deployment environment.
env := "tofu/talos-cluster/envs/kellerIO"

# List available recipes.
default:
    @just --list

# tofu init — download pinned modules + providers.
init:
    tofu -chdir={{env}} init

# Format all OpenTofu files (check only — no in-place edits).
fmt:
    tofu fmt -check -recursive

# Format all OpenTofu files in place.
fmt-fix:
    tofu fmt -recursive

# Validate the configuration.
validate:
    tofu -chdir={{env}} validate

# Show the planned changes.
plan:
    tofu -chdir={{env}} plan

# Apply the changes.
apply:
    tofu -chdir={{env}} apply

# Forward any env-local recipe (e.g. `just env secrets-edit`).
env *ARGS:
    just --justfile {{env}}/justfile --working-directory {{env}} {{ARGS}}
