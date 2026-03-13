#!/bin/bash
# filepath: /usr/local/bin/get_worker_ips.sh

set -e

# Get the ECS task metadata
METADATA=$(curl -s http://169.254.170.2/v2/metadata)
CLUSTER=$(echo "$METADATA" | jq -r '.Cluster' | awk -F'/' '{print $NF}')
TASK_ARN=$(echo "$METADATA" | jq -r '.TaskARN')
AWS_REGION=$(echo "$METADATA" | jq -r '.AvailabilityZone' | sed 's/[a-z]$//')
SERVICE_NAME="govwifi-capacity-testing-svc-development"

# List all task ARNs in the service
TASK_ARNS=$(aws ecs list-tasks \
  --cluster "$CLUSTER" \
  --service-name "$SERVICE_NAME" \
  --region "$AWS_REGION" \
  --query 'taskArns[]' \
  --output text)

if [ -z "$TASK_ARNS" ]; then
  echo "Error: No tasks found in service"
  exit 1
fi

# Describe the tasks to get their ENI IDs
TASK_DETAILS=$(aws ecs describe-tasks \
  --cluster "$CLUSTER" \
  --tasks $TASK_ARNS \
  --region "$AWS_REGION")

ENI_IDS=$(echo "$TASK_DETAILS" | jq -r '.tasks[].attachments[] | select(.type == "ElasticNetworkInterface") | .details[] | select(.name == "networkInterfaceId") | .value' | tr '\n' ' ')

if [ -z "$ENI_IDS" ]; then
  echo "Error: No ENI IDs found"
  exit 1
fi

# Describe the network interfaces to get the private IPs
IPS=$(aws ec2 describe-network-interfaces \
  --network-interface-ids $ENI_IDS \
  --region "$AWS_REGION" \
  --query 'NetworkInterfaces[].PrivateIpAddress' \
  --output text)


# Replace spaces with commas and remove trailing comma

WORKER_IPS=$(echo $IPS | sed 's/ /,/g')
echo $WORKER_IPS