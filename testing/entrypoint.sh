#!/bin/bash
set -euo pipefail

REPO_URL="${RESUME_REPO_URL:-git@github.com:cwage/resume.git}"
BRANCH="${RESUME_BRANCH:-add-github-experience-multiline-yaml}"
DEPLOY_KEY="/run/secrets/deploy_key"

# Set up SSH with deploy key
if [ -f "${DEPLOY_KEY}" ]; then
  echo "==> Configuring SSH with deploy key"
  mkdir -p ~/.ssh
  cp "${DEPLOY_KEY}" ~/.ssh/id_ed25519
  chmod 600 ~/.ssh/id_ed25519
  # Add GitHub's host keys
  ssh-keyscan -t ed25519,rsa github.com >> ~/.ssh/known_hosts 2>/dev/null
else
  echo "WARNING: No deploy key found at ${DEPLOY_KEY}, git clone may fail for private repos"
fi

if [ -d /site/.git ]; then
  echo "==> Existing repo found, pulling latest from branch: ${BRANCH}"
  cd /site
  git fetch origin
  git checkout "${BRANCH}"
  git reset --hard "origin/${BRANCH}"
else
  echo "==> Cloning ${REPO_URL} (branch: ${BRANCH})"
  git clone -b "${BRANCH}" "${REPO_URL}" /site
  cd /site
fi

echo "==> Installing gems..."
bundle install

echo "==> Starting Jekyll on 0.0.0.0:4000"
exec bundle exec jekyll serve --host 0.0.0.0
