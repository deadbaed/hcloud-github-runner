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

# Create a Forgejo Actions Runner in Hetzner Cloud
# https://docs.hetzner.cloud/#servers-create-a-server

# Function to exit the script with a failure message
function exit_with_failure() {
	echo >&2 "FAILURE: $1"  # Print error message to stderr
	exit 1
}

# Define required commands
MY_COMMANDS=(
	base64
	curl
	cut
	envsubst
	jq
)
# Check if required commands are available
for MY_COMMAND in "${MY_COMMANDS[@]}"; do
	if ! command -v "$MY_COMMAND" >/dev/null 2>&1; then
		exit_with_failure "The command '$MY_COMMAND' was not found. Please install it."
	fi
done

# Check if files exist
MY_FILES=(
	"cloud-init.template.yml"
	"create-server.template.json"
	"install.sh"
)
# Check if required commands are available
for MY_FILE in "${MY_FILES[@]}"; do
	if [[ ! -f "$MY_FILE" ]]; then
		exit_with_failure "The file '$MY_FILE' was not found!"
	fi
done

#
# INPUT
#

# GitHub Actions inputs
# https://docs.github.com/en/actions/sharing-automations/creating-actions/metadata-syntax-for-github-actions#inputs
# When you specify an input, GitHub creates an environment variable for the input with the name INPUT_<VARIABLE_NAME>.

# Specify here which mode you want to use (default: create):
# - create : Create a new runner
# - delete : Delete the previously created runner
# If INPUT_MODE is set, use its value; otherwise, use "create".
MY_MODE=${INPUT_MODE:-"create"}
if [[ "$MY_MODE" != "create" && "$MY_MODE" != "delete" ]]; then
	exit_with_failure "Mode must be 'create' or 'delete'."
fi

# Set the Hetzner Cloud API token.
# Retrieves the value from the INPUT_HCLOUD_TOKEN environment variable.
MY_HETZNER_TOKEN=${INPUT_HCLOUD_TOKEN}
if [[ -z "$MY_HETZNER_TOKEN" ]]; then
	exit_with_failure "Hetzner Cloud API token is not set."
fi

# Set the Forgejo Action Registration Token, to register runner to the instance
# It can be for the whole instance, for a user, or for just a single repository.
# Retrieves the value from the INPUT_FORGEJO_RUNNER_REGISTRATION_TOKEN environment variable.
MY_FORGEJO_RUNNER_REGISTRATION_TOKEN=${INPUT_FORGEJO_RUNNER_REGISTRATION_TOKEN}
if [[ -z "$MY_FORGEJO_RUNNER_REGISTRATION_TOKEN" && "$MY_MODE" == "create" ]]; then
	# Require runner registration token only in "create" mode, since it is useless in delete mode
	# (and the api does not support runner deletion yet)
	exit_with_failure "Forgejo Runner Registration Token is required!"
fi

# Set the GitHub repository name.
# This retrieves the value from the GITHUB_ACTION_REPOSITORY environment variable,
# which is automatically set in GitHub Actions workflows.
# https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/store-information-in-variables#default-environment-variables
MY_GITHUB_REPOSITORY=${GITHUB_REPOSITORY}
if [[ -z "$MY_GITHUB_REPOSITORY" ]]; then
	exit_with_failure "GitHub repository is required!"
fi

# Enable IPv4 (default: false)
# If INPUT_ENABLE_IPV4 is set, use its value; otherwise, use "false".
MY_ENABLE_IPV4=${INPUT_ENABLE_IPV4:-"true"}
if [[ "$MY_ENABLE_IPV4" != "true" && "$MY_ENABLE_IPV4" != "false" ]]; then
	exit_with_failure "Enable IPv4 must be 'true' or 'false'."
fi

# Enable IPv6 (default: true)
# If INPUT_ENABLE_IPV6 is set, use its value; otherwise, use "true".
MY_ENABLE_IPV6=${INPUT_ENABLE_IPV6:-"true"}
if [[ "$MY_ENABLE_IPV6" != "true" && "$MY_ENABLE_IPV6" != "false" ]]; then
	exit_with_failure "Enable IPv6 must be 'true' or 'false'."
fi

# Set the image to use for the instance (default: ubuntu-24.04)
# If INPUT_IMAGE is set, use its value; otherwise, use "ubuntu-24.04".
MY_IMAGE=${INPUT_IMAGE:-"ubuntu-24.04"}
# Check allowed characters
if [[ ! "$MY_IMAGE" =~ ^[a-zA-Z0-9\._-]{1,63}$ ]]; then
	exit_with_failure "'$MY_IMAGE' is not a valid OS image name!"
fi

# Set the location/region for the instance (default: nbg1)
# If INPUT_LOCATION is set, use its value; otherwise, use "nbg1".
MY_LOCATION=${INPUT_LOCATION:-"nbg1"}

# Set the name of the instance (default: forgejo-runner-$RANDOM)
# If INPUT_NAME is set, use its value; otherwise, generate a random name using "forgejo-runner-$RANDOM".
MY_NAME=${INPUT_NAME:-"forgejo-runner-$RANDOM"}
# Check allowed characters
if [[ ! "$MY_NAME" =~ ^[a-zA-Z0-9_-]{1,64}$ ]]; then
	exit_with_failure "'$MY_NAME' is not a valid hostname or label!"
fi
if [[ "$MY_NAME" == "hetzner" ]]; then
	exit_with_failure "'hetzner' is not allowed as hostname!"
fi

# Set the network for the instance (default: null)
# If INPUT_NETWORK is set, use its value; otherwise, use "null".
MY_NETWORK=${INPUT_NETWORK:-"null"}
# Check if MY_NETWORK is an integer
if [[ "$MY_NETWORK" != "null" && ! "$MY_NETWORK" =~ ^[0-9]+$ ]]; then
	exit_with_failure "The network ID must be 'null' or an integer!"
fi

# Set bash commands to run before the runner starts.
# If INPUT_PRE_RUNNER_SCRIPT is set, use its value; otherwise, use "".
MY_PRE_RUNNER_SCRIPT=${INPUT_PRE_RUNNER_SCRIPT:-""}

# Set the primary IPv4 address for the instance (default: null)
# If INPUT_PRIMARY_IPV4 is set, use its value; otherwise, use "null".
MY_PRIMARY_IPV4=${INPUT_PRIMARY_IPV4:-"null"}
# Check if MY_PRIMARY_IPV4 is an integer
if [[ "$MY_PRIMARY_IPV4" != "null" && ! "$MY_PRIMARY_IPV4" =~ ^[0-9]+$ ]]; then
	exit_with_failure "The primary IPv4 ID must be 'null' or an integer!"
fi

# Set the primary IPv6 address for the instance (default: null)
# If INPUT_PRIMARY_IPV6 is set, use its value; otherwise, use "null".
MY_PRIMARY_IPV6=${INPUT_PRIMARY_IPV6:-"null"}
# Check if MY_PRIMARY_IPV6 is an integer
if [[ "$MY_PRIMARY_IPV6" != "null" && ! "$MY_PRIMARY_IPV6" =~ ^[0-9]+$ ]]; then
	exit_with_failure "The primary IPv6 ID must be 'null' or an integer!"
fi

# Set the server type/instance type (default: cx22)
# If INPUT_SERVER_TYPE is set, use its value; otherwise, use "cx22".
MY_SERVER_TYPE=${INPUT_SERVER_TYPE:-"cx22"}

# Set maximal wait time (retries * 10 sec) for Hetzner Cloud Server (default: 30 [5 min])
# If INPUT_SERVER_WAIT is set, use its value; otherwise, use "30".
MY_SERVER_WAIT=${INPUT_SERVER_WAIT:-"30"}
# Check if MY_SERVER_WAIT is an integer
if [[ ! "$MY_SERVER_WAIT" =~ ^[0-9]+$ ]]; then
	exit_with_failure "The maximum wait time (reties) for a running Hetzner Cloud Server must be an integer!"
fi

# Set the SSH key to use for the instance (default: null)
# If INPUT_SSH_KEY is set, use its value; otherwise, use "null".
MY_SSH_KEY=${INPUT_SSH_KEY:-"null"}
# Check if MY_SSH_KEY is an integer
if [[ "$MY_SSH_KEY" != "null" && ! "$MY_SSH_KEY" =~ ^[0-9]+$ ]]; then
	exit_with_failure "The SSH key ID must be 'null' or an integer!"
fi

# Set default Forgejo Actions Runner installation directory (default: /run/forgejo-runner)
# If INPUT_RUNNER_DIR is set, its value is used. Otherwise, the default value /run/forgejo-runner is used.
MY_RUNNER_DIR=${INPUT_RUNNER_DIR:-"/run/forgejo-runner"}
# Check allowed characters
if [[ ! "$MY_RUNNER_DIR" =~ ^/([^/]+/)*[^/]+$ ]]; then
	exit_with_failure "'$MY_RUNNER_DIR' is not a valid absolute directory path without a trailing slash!"
fi

# Set default Forgejo Actions Runner version (default: latest)
# If INPUT_RUNNER_VERSION is set, its value is used. Otherwise, the default value "latest" is used.
# Releases: https://code.forgejo.org/forgejo/runner/releases
MY_RUNNER_VERSION=${INPUT_RUNNER_VERSION:-"latest"}
# Check allowed values
if [[ "$MY_RUNNER_VERSION" != "latest" && "$MY_RUNNER_VERSION" != "skip" && ! "$MY_RUNNER_VERSION" =~ ^[0-9\.]{1,63}$ ]]; then
	exit_with_failure "'$MY_RUNNER_VERSION' is not a valid Forgejo Actions Runner version! Enter 'latest', 'skip' or the version without 'v'."
fi

# Set maximal wait time (retries * 10 sec) for Forgejo Actions Runner registration (default: 30 [5 min])
# If MY_RUNNER_WAIT is set, use its value; otherwise, use "30".
MY_RUNNER_WAIT=${INPUT_RUNNER_WAIT:-"60"}
# Check if MY_RUNNER_WAIT is an integer
if [[ ! "$MY_RUNNER_WAIT" =~ ^[0-9]+$ ]]; then
	exit_with_failure "The maximum wait time (reties) for Forgejo Action Runner registration must be an integer!"
fi

# Forgejo: Create and use ssh key to get Actions Runner registration status
# If INPUT_FORGEJO_USE_SSH_FOR_RUNNER_WAIT is set, use its value; otherwise, use "false".
MY_FORGEJO_USE_SSH_FOR_RUNNER_WAIT=${INPUT_FORGEJO_USE_SSH_FOR_RUNNER_WAIT:-"false"}
if [[ "$MY_FORGEJO_USE_SSH_FOR_RUNNER_WAIT" != "true" && "$MY_FORGEJO_USE_SSH_FOR_RUNNER_WAIT" != "false" ]]; then
	exit_with_failure "Use ssh key to get runner registration status 'true' or 'false'."
fi


# Set Hetzner Cloud Server ID
MY_HETZNER_SERVER_ID=${INPUT_SERVER_ID}


#
# DELETE
#

if [[ "$MY_MODE" == "delete" ]]; then
	# Check if MY_HETZNER_SERVER_ID is an integer
	if [[ ! "$MY_HETZNER_SERVER_ID" =~ ^[0-9]+$ ]]; then
		exit_with_failure "Failed to get ID of the Hetzner Cloud Server!"
	fi

	# Send a DELETE request to the Hetzner Cloud API to delete the server.
	# https://docs.hetzner.cloud/#servers-delete-a-server
	echo "Delete server..."
	curl \
		-X DELETE \
		--fail-with-body \
		-H "Content-Type: application/json" \
		-H "Authorization: Bearer ${MY_HETZNER_TOKEN}" \
		"https://api.hetzner.cloud/v1/servers/$MY_HETZNER_SERVER_ID" \
		|| exit_with_failure "Error deleting server!"
	echo "Hetzner Cloud Server deleted successfully."

	echo "The Hetzner Cloud Server has been deleted successfully."
	echo "Forgejo Actions Runner was not deleted. Please delete manually: ${GITHUB_SERVER_URL}/${MY_GITHUB_REPOSITORY}/settings/actions/runners/"
	# Add GitHub Action job summary 
	# https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/workflow-commands-for-github-actions#adding-a-job-summary
	echo "The Hetzner Cloud Server has been deleted successfully 🗑️" >> "$GITHUB_STEP_SUMMARY"
	exit 0
fi

#
# CREATE
#

# Forgejo: If asked: generate ssh key, and upload to Hetzner
if [[ "$MY_FORGEJO_USE_SSH_FOR_RUNNER_WAIT" == "true" ]]; then
	MY_FORGEJO_RUNNER_WAIT_SSH_DIR="$(mktemp -d /tmp/forgejo_ssh_for_runner_wait.XXXX)"
	MY_FORGEJO_RUNNER_WAIT_SSH_KEY="${MY_FORGEJO_RUNNER_WAIT_SSH_DIR}/id_ed25519"
	MY_FORGEJO_RUNNER_WAIT_SSH_PUB="${MY_FORGEJO_RUNNER_WAIT_SSH_DIR}/id_ed25519.pub"

	# ed25519 key without passphrase
	ssh-keygen -f $MY_FORGEJO_RUNNER_WAIT_SSH_KEY -t ed25519 -N ""

	echo "Uploading ssh key..."
	if ! curl \
		-X POST \
		--fail-with-body \
		-o "ssh_keys.json" \
		-H "Content-Type: application/json" \
		-H "Authorization: Bearer ${MY_HETZNER_TOKEN}" \
		--data "$(jq -n --arg name "$MY_NAME" --arg public_key "$(cat "${MY_FORGEJO_RUNNER_WAIT_SSH_PUB}")" '{"name": $name, "public_key": $public_key}')" \
		"https://api.hetzner.cloud/v1/ssh_keys"; then
			cat "ssh_keys.json"
			exit_with_failure "Failed to upload ssh key in Hetzner Cloud!"
	fi

	# Get the Hetzner Server ID from the JSON response (assuming valid JSON)
	MY_FORGEJO_RUNNER_WAIT_SSH_HETZNER_ID=$(jq -er '.ssh_key.id' < "ssh_keys.json")

	# Check if MY_FORGEJO_RUNNER_WAIT_SSH_HETZNER_ID is an integer
	if [[ ! "$MY_FORGEJO_RUNNER_WAIT_SSH_HETZNER_ID" =~ ^[0-9]+$ ]]; then
		exit_with_failure "Failed to get ID of the SSH key uploaded in Hetzner Cloud!"
	fi
fi

# Encode the contents of the "install.sh" and runner script into base64
# BSD
if [[ "$OSTYPE" == "darwin"* || "$OSTYPE" == "freebsd"* ]]; then
	MY_INSTALL_SH_BASE64=$(base64 < "install.sh")
	MY_PRE_RUNNER_SCRIPT_BASE64=$(echo "$MY_PRE_RUNNER_SCRIPT" | base64)
# GNU Core tools
else
	MY_INSTALL_SH_BASE64=$(base64 --wrap=0 < "install.sh")
	MY_PRE_RUNNER_SCRIPT_BASE64=$(echo "$MY_PRE_RUNNER_SCRIPT" | base64 --wrap=0)
fi

# Split protocol from instance url, Hetzner does not allow "/" in label values
FORGEJO_INSTANCE="${GITHUB_SERVER_URL#*://}"

# Replace "/" by "_" in repository name, Hetzner does not allow "/" in label values
FORGEJO_REPOSITORY="${MY_GITHUB_REPOSITORY//\//_}"

# Export environment variables for use in the cloud-init template
export GITHUB_SERVER_URL
export MY_FORGEJO_RUNNER_REGISTRATION_TOKEN
export MY_INSTALL_SH_BASE64
export MY_NAME
export MY_PRE_RUNNER_SCRIPT_BASE64
export MY_RUNNER_DIR
export MY_RUNNER_VERSION
# Substitute environment variables in the cloud-init template and create the final cloud-init configuration
if [[ ! -f "cloud-init.template.yml" ]]; then
	exit_with_failure "cloud-init.template.yml not found!"
fi
envsubst < cloud-init.template.yml > cloud-init.yml

# Generate the create-server.json file by populating the create-server.template.json template with variables.
# This uses jq to construct a JSON object based on the template and provided arguments.
# Optimize values for valid labels: https://docs.hetzner.cloud/#labels
echo "Generate server configuration..."
jq -n \
	--arg location "$MY_LOCATION" \
	--arg runner_version "$MY_RUNNER_VERSION" \
	--arg forgejo_instance "$FORGEJO_INSTANCE" \
	--arg forgejo_repository "$FORGEJO_REPOSITORY" \
	--arg image "$MY_IMAGE" \
	--arg server_type "$MY_SERVER_TYPE" \
	--arg name "$MY_NAME" \
	--argjson enable_ipv4 "$MY_ENABLE_IPV4" \
	--argjson enable_ipv6 "$MY_ENABLE_IPV6" \
	--rawfile cloud_init_yml "cloud-init.yml" \
	-f create-server.template.json > create-server.json \
	|| exit_with_failure "Failed to generate create-server.json!"
# Add the primary IPv4 address if available (not "null")
if [[ "$MY_PRIMARY_IPV4" != "null" ]]; then
	cp create-server.json create-server-ipv4.json && \
	jq ".public_net.ipv4 = $MY_PRIMARY_IPV4" < create-server-ipv4.json > create-server.json && \
	echo "Primary IPv4 ID added to create-server.json."
fi
# Add the primary IPv6 address if available (not "null")
if [[ "$MY_PRIMARY_IPV6" != "null" ]]; then
	cp create-server.json create-server-ipv6.json && \
	jq ".public_net.ipv6 = $MY_PRIMARY_IPV6" < create-server-ipv6.json > create-server.json && \
	echo "Primary IPv6 ID added to create-server.json."
fi
# Add SSH key configuration to the create-server.json file if MY_SSH_KEY is not "null".
if [[ "$MY_SSH_KEY" != "null" ]]; then
	cp create-server.json create-server-ssh.json && \
	jq ".ssh_keys += [$MY_SSH_KEY]" < create-server-ssh.json > create-server.json && \
	echo "SSH key added to create-server.json."
fi
# Forgejo: Add SSH key created to the create-server.json file if asked
if [[ "$MY_FORGEJO_USE_SSH_FOR_RUNNER_WAIT" == "true" ]]; then
	cp create-server.json create-server-ssh.json && \
	jq ".ssh_keys += [$MY_FORGEJO_RUNNER_WAIT_SSH_HETZNER_ID]" < create-server-ssh.json > create-server.json && \
	echo "SSH key for getting status of runner registration added to create-server.json."
fi
# Add network configuration to the create-server.json file if MY_NETWORK is not "null".
if [[ "$MY_NETWORK" != "null" ]]; then
	cp create-server.json create-server-network.json && \
	jq ".networks += [$MY_NETWORK]" < create-server-network.json > create-server.json && \
	echo "Network added to create-server.json."
fi

# Send a POST request to the Hetzner Cloud API to create a server.
# https://docs.hetzner.cloud/#servers-create-a-server
echo "Create server..."
if ! curl \
	-X POST \
	--fail-with-body \
	-o "servers.json" \
	-H "Content-Type: application/json" \
	-H "Authorization: Bearer ${MY_HETZNER_TOKEN}" \
	-d @create-server.json \
	"https://api.hetzner.cloud/v1/servers"; then
	cat "servers.json"
	exit_with_failure "Failed to create Server in Hetzner Cloud!"
fi

# Get the Hetzner Server ID from the JSON response (assuming valid JSON)
MY_HETZNER_SERVER_ID=$(jq -er '.server.id' < "servers.json")

# Check if MY_HETZNER_SERVER_ID is an integer
if [[ ! "$MY_HETZNER_SERVER_ID" =~ ^[0-9]+$ ]]; then
	exit_with_failure "Failed to get ID of the Hetzner Cloud Server!"
fi

# Set GitHub Action output
# https://github.blog/changelog/2022-10-11-github-actions-deprecating-save-state-and-set-output-commands/
#echo "::set-output name=label::$MY_NAME"
#echo "::set-output name=server_id::$MY_HETZNER_SERVER_ID"
echo "label=$MY_NAME" >> "$GITHUB_OUTPUT"
echo "server_id=$MY_HETZNER_SERVER_ID" >> "$GITHUB_OUTPUT"

# Wait for server
MAX_RETRIES=$MY_SERVER_WAIT
WAIT_SEC=10
RETRY_COUNT=0
echo "Wait for server..."
while [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; do
	# Download and parse server status
	# https://docs.hetzner.cloud/#servers-get-a-server
	curl -s \
		-o "servers.json" \
		-H "Content-Type: application/json" \
		-H "Authorization: Bearer ${MY_HETZNER_TOKEN}" \
		"https://api.hetzner.cloud/v1/servers/$MY_HETZNER_SERVER_ID" \
		|| exit_with_failure "Failed to get status of the Hetzner Cloud Server!"

	MY_HETZNER_SERVER_STATUS=$(jq -er '.server.status' < "servers.json")

	# Check if server is running
	if [[ "$MY_HETZNER_SERVER_STATUS" == "running" ]]; then
		echo "Server is running."
		break
	fi

	RETRY_COUNT=$((RETRY_COUNT + 1)) # Increment retry counter

	echo "Server is not running yet. Waiting $WAIT_SEC seconds... (Attempt $RETRY_COUNT/$MAX_RETRIES)"
	sleep "$WAIT_SEC"
done
if [[ "$MY_HETZNER_SERVER_STATUS" != "running" ]]; then
	exit_with_failure "Failed to start Hetzner Cloud Server! Please check manually."
fi

# Special for Forgejo, since we cannot use its api to get registration status
if [[ "$MY_FORGEJO_USE_SSH_FOR_RUNNER_WAIT" == "true" ]]; then
	# Wait for Forgejo Actions Runner registration
	MAX_RETRIES=$MY_RUNNER_WAIT
	RETRY_COUNT=0
	echo "Wait for Forgejo Actions Runner registration..."
	while [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; do

		# Extract IPv4 and IPv6 addresses
		MY_FORGEJO_USE_SSH_IPV4=$(jq -r '.server.public_net.ipv4.ip' "servers.json")
		MY_FORGEJO_USE_SSH_IPV6=$(jq -r '.server.public_net.ipv6.ip' "servers.json")

		# Determine which IP to use
		if [ "$MY_FORGEJO_USE_SSH_IPV4" != "null" ]; then
			MY_FORGEJO_USE_SSH_IP=$MY_FORGEJO_USE_SSH_IPV4
		else
			# Have a complete ipv6
			MY_FORGEJO_USE_SSH_IP="${MY_FORGEJO_USE_SSH_IPV6%::*}::1"
		fi

		# Get status of runner via ssh
		MY_FORGEJO_RUNNER_REGISTRATION_STATUS=$(ssh -i "$MY_FORGEJO_RUNNER_WAIT_SSH_KEY" -o "StrictHostKeyChecking no" root@"$MY_FORGEJO_USE_SSH_IP" "systemctl is-active forgejo-runner")
		if [[ "$MY_FORGEJO_RUNNER_REGISTRATION_STATUS" == "active" ]]; then
			echo "Forgejo Actions Runner registered."
			break
		fi

		RETRY_COUNT=$((RETRY_COUNT + 1)) # Increment retry counter

		echo "Forgejo Actions Runner is not yet registered. Wait $WAIT_SEC seconds... (Attempt $RETRY_COUNT/$MAX_RETRIES)"
		sleep "$WAIT_SEC"
	done

	# Delete ssh key, since we do not need it anymore
	echo "Delete ssh key..."
	rm $MY_FORGEJO_RUNNER_WAIT_SSH_KEY
	curl \
		-X DELETE \
		--fail-with-body \
		-H "Content-Type: application/json" \
		-H "Authorization: Bearer ${MY_HETZNER_TOKEN}" \
		"https://api.hetzner.cloud/v1/ssh_keys/$MY_FORGEJO_RUNNER_WAIT_SSH_HETZNER_ID" \
		|| exit_with_failure "Error deleting ssh key!"
	echo "SSH key deleted successfully from Hetzner Cloud Server."

	if [[ "$MY_FORGEJO_RUNNER_REGISTRATION_STATUS" != "active" ]]; then
		exit_with_failure "Forgejo Actions Runner is not registered. Please check installation manually."
	fi
fi

# TODO: since forgejo does not support getting status of runners through its api, here's a way of knowing if the runner is ready:
# 1. create a throwaway ssh keypair, upload it to hetzner and use it during server creation.
# 2. when server is ready, (watch out for ipv4/ipv6) use that key to run `ssh root@ip_of_server "systemctl is-active forgejo-runner" > result`
# 3. result must be "active", else loop
# 4. at the end, whatever happens, delete the ssh key on hetzner to not pollute accoun.t

echo
echo "The Hetzner Cloud Server and its associated Forgejo Actions Runner are ready for use." 
echo "Runner: ${GITHUB_SERVER_URL}/${MY_GITHUB_REPOSITORY}/settings/actions/runners/"
# Add GitHub Action job summary 
# https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/workflow-commands-for-github-actions#adding-a-job-summary
echo "The Hetzner Cloud Server and its associated [Forgejo Actions Runner](${GITHUB_SERVER_URL}/${MY_GITHUB_REPOSITORY}/settings/actions/runners/) are ready for use 🚀" >> "$GITHUB_STEP_SUMMARY"
exit 0
