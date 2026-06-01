#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$script_dir"

cmd="${1:-plan}"

if [ "$cmd" = "init" ]; then
  terraform init
  exit 0
fi

if [ ! -f terraform.tfvars ]; then
  printf '%s\n' 'terraform.tfvars not found. Copy terraform.tfvars.example and fill in values before applying.'
fi

terraform init
terraform fmt -check -recursive
terraform validate

case "$cmd" in
  plan)
    terraform plan
    ;;
  apply)
    terraform apply
    ;;
  destroy)
    terraform destroy
    ;;
  *)
    printf '%s\n' 'Usage: deploy.sh [init|plan|apply|destroy]'
    exit 1
    ;;
esac