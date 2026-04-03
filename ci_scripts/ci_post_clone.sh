#!/bin/sh
set -e

# Xcode Cloud post-clone script
# Runs after the repository is cloned, before dependency resolution.

echo "=== ci_post_clone.sh ==="
echo "Build number: $CI_BUILD_NUMBER"
echo "Workflow: $CI_WORKFLOW"
echo "Branch: $CI_BRANCH"
echo "Post-clone script completed successfully."
