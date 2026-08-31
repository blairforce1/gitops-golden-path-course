# Identity facts for THIS instance of the walkthrough - derived live, stored nowhere.
# Every paste block that needs identity starts with `source ./env.sh`; this file is
# committed but contains no account names, so the tutorial works for any fork.
# (GHCR image names must be lowercase, hence the tr.)
export GH_OWNER=$(gh api user --jq .login | tr '[:upper:]' '[:lower:]')
export CONFIG_REPO=$(basename -s .git "$(git remote get-url origin)")
export APP_REPO=gitops-golden-path-app
export APP_DIR="$(git rev-parse --show-toplevel)/../$APP_REPO"
export APP_IMAGE="ghcr.io/$GH_OWNER/$APP_REPO"
