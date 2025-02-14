#!/usr/bin/env bash

# Copyright 2024 Nils Knieling. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Install Forgejo Actions Runner for Linux with x64 or ARM64 CPU architecture
# https://code.forgejo.org/forgejo/runner
# https://forgejo.org/docs/next/admin/runner-installation/

# Get the script's name
MY_SCRIPT_NAME=$(basename "$0")

# Set default Forgejo Actions Runner version (latest)
MY_RUNNER_VERSION="latest"

# Function to exit the script with a failure message
function exit_with_failure() {
	echo >&2 "FAILURE: $1"  # Print error message to stderr
	exit 1
}

# Function to display usage information
function usage {
	MY_RETURN_CODE="$1"
	echo -e "Usage: $MY_SCRIPT_NAME [-v <runner_version>] [-d <runner_dir>] [-h]:
	[-v <runner_version>]  Version (without 'v') of the Forgejo Actions Runner. (default: $MY_RUNNER_VERSION)
	[-d <runner_dir>]      Directory for the Forgejo Actions Runner installation. (default: $MY_RUNNER_DIR)
	[-h]                   Displays this message."
	exit "$MY_RETURN_CODE"
}

# If version is "skip", skip Forgejo Actions Runner installation.
if [[ "$MY_RUNNER_VERSION" = "skip" ]]; then
	exit 0
fi

# Define required commands
MY_COMMANDS=(
	curl
	jq
	gpg
	cut
	wget
)
# Check if required commands are available
for MY_COMMAND in "${MY_COMMANDS[@]}"; do
	if ! command -v "$MY_COMMAND" >/dev/null 2>&1; then
		exit_with_failure "The command '$MY_COMMAND' was not found. Please install it."
	fi
done

# Detect CPU architecture
case $(uname -m) in
aarch64|arm64)
	MY_ARCH="arm64"
	;;
amd64|x86_64)
	MY_ARCH="amd64"
	;;
*)
	exit_with_failure "Cannot determine CPU architecture!"
esac

# Process command line arguments
while getopts ":v:d:h" opt; do
	case $opt in
	v)
		MY_RUNNER_VERSION="$OPTARG"
		;;
	d)
		MY_RUNNER_DIR="$OPTARG"
		;;
	h)
		usage 0
		;;
	*)
		echo "Invalid option: -$OPTARG"
		usage 1
		;;
	esac
done

# If version is "latest", fetch the latest version from Forgejo API
if [[ "$MY_RUNNER_VERSION" = "latest" ]]; then
	MY_RUNNER_LATEST_VERSION=$(curl -X 'GET' https://data.forgejo.org/api/v1/repos/forgejo/runner/releases/latest | jq .name -r | cut -c 2-)
	MY_RUNNER_VERSION="$MY_RUNNER_LATEST_VERSION"
	if [[ -z "$MY_RUNNER_LATEST_VERSION" || "null" == "$MY_RUNNER_LATEST_VERSION" ]]; then
		exit_with_failure "Could not retrieve the latest Forgejo Actions Runner version!"
	fi
	echo "Forgejo Actions Runner version 'v${MY_RUNNER_LATEST_VERSION}' is detected as the latest version."
else
	echo "Forgejo Actions Runner version 'v$MY_INPUT_RUNNER_VERSION' is specified as version."
	MY_RUNNER_VERSION="$MY_INPUT_RUNNER_VERSION"
fi

# Create directory (if it doesn't exist) and change to the installation directory
mkdir -p "$MY_RUNNER_DIR" && \
cd "$MY_RUNNER_DIR" && \
# Download runner
wget -O forgejo-runner "https://data.forgejo.org/forgejo/runner/releases/download/v${MY_RUNNER_VERSION}/forgejo-runner-${MY_RUNNER_VERSION}-linux-${MY_ARCH}" && \
# Download and verify signature
wget -O forgejo-runner.asc "https://data.forgejo.org/forgejo/runner/releases/download/v${MY_RUNNER_VERSION}/forgejo-runner-${MY_RUNNER_VERSION}-linux-${MY_ARCH}.asc" && \
gpg --keyserver keys.openpgp.org --recv EB114F5E6C0DC2BCDD183550A4B61A2DC5923710 && \
gpg --verify forgejo-runner.asc forgejo-runner && \
# Copy binary to path
cp forgejo-runner /usr/local/bin/forgejo-runner && \
chmod +x /usr/local/bin/forgejo-runner

# Register runner
/usr/local/bin/forgejo-runner register --no-interactive --instance "${GITHUB_SERVER_URL}" --token "${MY_FORGEJO_RUNNER_REGISTRATION_TOKEN}" --name "${MY_NAME}" --labels "${MY_NAME},self-hosted:host://-self-hosted,hetzner" 

