# Resume preview

Preview a resume branch at `preview.quietlife.net` before merging to master/GitHub Pages. This uses a Jekyll container deployed to the containers host.

## Commands

| Command | Description |
|---------|-------------|
| `make ansible-testing-deploy` | Full deploy (copy files, build, start container) |
| `make ansible-testing-deploy-check` | Dry-run deploy |
| `make ansible-testing-refresh` | Restart container (pulls latest from current branch) |
| `make ansible-testing-switch BRANCH=master` | Switch to a different branch and restart |
| `make testing-build` | Build the Docker image locally |

## Day-to-day workflow

Edit resume locally, `git push`, then `make ansible-testing-refresh` to see changes at `preview.quietlife.net`.
