import json
import time
import uuid
from os import path as osp, remove
from shutil import rmtree
from textwrap import dedent

import pytest
from infrahouse_core.aws.ec2_instance import EC2Instance
from pytest_infrahouse import terraform_apply

from tests.conftest import (
    LOG,
)


def verify_cloudwatch_integration(
    instance, boto3_session, aws_region, cloudwatch_namespace, log_group_name
):
    """
    Verify CloudWatch Logs and Metrics integration for terraformer instance.

    Validates:
    1. CloudWatch Log Group exists in AWS
    2. End-to-end: instance can create log stream and put log events using AWS CLI
    3. End-to-end: pytest can read the log events from CloudWatch
    4. End-to-end: instance can publish metrics to the namespace
    """
    LOG.info("Testing CloudWatch integration (Logs + Metrics)...")

    # 1. Wait for Puppet to complete (marked by /var/run/puppet-done)
    LOG.info("1. Waiting for Puppet to complete bootstrap (up to 10 minutes)...")
    max_wait = 600  # 10 minutes
    poll_interval = 10
    puppet_done = False

    for attempt in range(max_wait // poll_interval):
        exit_code, stdout, stderr = instance.execute_command(
            "test -f /var/run/puppet-done && echo 'done' || echo 'not done'"
        )

        if exit_code == 0 and stdout.strip() == "done":
            puppet_done = True
            LOG.info(
                f"✓ Puppet bootstrap completed (after {(attempt + 1) * poll_interval} seconds)"
            )
            break

        LOG.info(
            f"   Puppet still running (attempt {attempt + 1}/{max_wait // poll_interval})..."
        )
        time.sleep(poll_interval)

    assert puppet_done, (
        f"Puppet bootstrap did not complete after {max_wait} seconds. "
        f"Marker file /var/run/puppet-done not found."
    )

    # 2. Verify CloudWatch Log Group exists in AWS
    LOG.info("2. Verifying CloudWatch Log Group exists in AWS...")
    logs_client = boto3_session.client("logs", region_name=aws_region)

    try:
        response = logs_client.describe_log_groups(
            logGroupNamePrefix=log_group_name, limit=1
        )
        log_groups = response.get("logGroups", [])
        assert (
            len(log_groups) > 0
        ), f"Log group {log_group_name} not found in CloudWatch"

        log_group = log_groups[0]
        assert (
            log_group["logGroupName"] == log_group_name
        ), f"Log group name mismatch: {log_group['logGroupName']} != {log_group_name}"

        LOG.info("✓ CloudWatch Log Group exists: %s", log_group_name)
        LOG.info(
            "  Retention: %s days", log_group.get("retentionInDays", "Never expire")
        )

    except Exception as e:
        pytest.fail(f"Failed to verify CloudWatch Log Group: {e}")

    # 3. Verify end-to-end logging using AWS CLI from instance
    LOG.info("3. Verifying end-to-end CloudWatch Logs integration...")

    # Generate unique test message and log stream
    test_message = f"TERRAFORMER_TEST_LOG_{uuid.uuid4().hex}"
    log_stream_name = f"test-stream-{uuid.uuid4().hex[:8]}"

    # Create log stream from instance using AWS CLI
    LOG.info(f"  Creating log stream '{log_stream_name}'...")
    exit_code, stdout, stderr = instance.execute_command(
        f'aws logs create-log-stream --log-group-name "{log_group_name}" '
        f'--log-stream-name "{log_stream_name}" --region {aws_region}'
    )
    assert exit_code == 0, f"Failed to create log stream. stderr: {stderr}"

    # Put log event from instance
    LOG.info(f"  Putting log event with message: {test_message}")
    timestamp_ms = int(time.time() * 1000)
    exit_code, stdout, stderr = instance.execute_command(
        f'aws logs put-log-events --log-group-name "{log_group_name}" '
        f'--log-stream-name "{log_stream_name}" '
        f'--log-events timestamp={timestamp_ms},message="{test_message}" '
        f"--region {aws_region}"
    )
    assert exit_code == 0, f"Failed to put log event. stderr: {stderr}"

    # Verify log appears in CloudWatch from pytest
    LOG.info("  Verifying pytest can read the log event...")
    max_wait = 30
    poll_interval = 5
    message_found = False

    for attempt in range(max_wait // poll_interval):
        time.sleep(poll_interval)

        try:
            response = logs_client.get_log_events(
                logGroupName=log_group_name,
                logStreamName=log_stream_name,
                limit=10,
                startFromHead=True,
            )

            for event in response.get("events", []):
                if test_message in event.get("message", ""):
                    message_found = True
                    LOG.info(
                        f"  ✓ Test message found in CloudWatch after {(attempt + 1) * poll_interval} seconds"
                    )
                    break

            if message_found:
                break

        except logs_client.exceptions.ResourceNotFoundException:
            LOG.info(
                f"  Log stream not found yet (attempt {attempt + 1}/{max_wait // poll_interval})..."
            )
            continue

    assert message_found, (
        f"Test message not found in CloudWatch Logs after {max_wait} seconds. "
        f"Log group: {log_group_name}, Log stream: {log_stream_name}"
    )

    LOG.info("✓ End-to-end CloudWatch Logs integration verified")

    # 5. Verify end-to-end metrics integration
    LOG.info("5. Verifying end-to-end CloudWatch Metrics integration...")

    # Generate unique metric name
    test_metric_name = f"TestMetric_{uuid.uuid4().hex[:8]}"
    test_metric_value = 42.0

    # Put metric from instance using AWS CLI
    LOG.info(
        f"  Publishing test metric '{test_metric_name}' to namespace '{cloudwatch_namespace}'..."
    )
    exit_code, stdout, stderr = instance.execute_command(
        f'aws cloudwatch put-metric-data --namespace "{cloudwatch_namespace}" '
        f'--metric-name "{test_metric_name}" --value {test_metric_value} --region {aws_region}'
    )
    assert exit_code == 0, f"Failed to publish metric. stderr: {stderr}"

    # Verify metric appears in CloudWatch
    LOG.info("  Waiting for metric to appear in CloudWatch (up to 60 seconds)...")
    cloudwatch_client = boto3_session.client("cloudwatch", region_name=aws_region)
    max_wait = 60
    poll_interval = 5
    metric_found = False

    for attempt in range(max_wait // poll_interval):
        time.sleep(poll_interval)

        try:
            response = cloudwatch_client.list_metrics(
                Namespace=cloudwatch_namespace, MetricName=test_metric_name
            )

            if response.get("Metrics"):
                metric_found = True
                LOG.info(
                    f"  ✓ Test metric found in CloudWatch after {(attempt + 1) * poll_interval} seconds"
                )
                break

        except Exception as e:
            LOG.info(
                f"  Error checking metric (attempt {attempt + 1}/{max_wait // poll_interval}): {e}"
            )
            continue

    assert metric_found, (
        f"Test metric '{test_metric_name}' not found in CloudWatch after {max_wait} seconds. "
        f"Namespace: {cloudwatch_namespace}"
    )

    LOG.info("✓ End-to-end CloudWatch Metrics integration verified")
    LOG.info("✅ All CloudWatch integration tests passed!")


@pytest.mark.parametrize(
    "aws_provider_version", ["~> 5.62", "~> 6.0"], ids=["aws-5", "aws-6"]
)
def test_module(
    aws_region,
    keep_after,
    test_role_arn,
    service_network,
    subzone,
    aws_provider_version,
    boto3_session,
):
    terraform_root_dir = "test_data"

    LOG.info(json.dumps(service_network, indent=4))

    subnet_public_ids = service_network["subnet_public_ids"]["value"]
    subnet_private_ids = service_network["subnet_private_ids"]["value"]
    terraform_module_dir = osp.join(terraform_root_dir, "terraformer")

    # Clean up state files to ensure fresh provider version
    state_files = [
        osp.join(terraform_module_dir, ".terraform"),
        osp.join(terraform_module_dir, ".terraform.lock.hcl"),
    ]

    for state_file in state_files:
        try:
            if osp.isdir(state_file):
                rmtree(state_file)
            elif osp.isfile(state_file):
                remove(state_file)
        except FileNotFoundError:
            pass

    # Create terraformer
    with open(osp.join(terraform_module_dir, "terraform.tfvars"), "w") as fp:
        fp.write(
            dedent(
                f"""
                region = "{aws_region}"
                test_zone_id = "{subzone["subzone_id"]["value"]}"

                subnet_public_ids = {json.dumps(subnet_public_ids)}
                subnet_private_ids = {json.dumps(subnet_private_ids)}
                """
            )
        )
        if test_role_arn:
            fp.write(
                dedent(
                    f"""
                    role_arn = "{test_role_arn}"
                    """
                )
            )

    with open(osp.join(terraform_module_dir, "terraform.tf"), "w") as fp:
        fp.write(
            dedent(
                f"""
                terraform {{
                  required_version = "~> 1.5"
                  //noinspection HILUnresolvedReference
                  required_providers {{
                    aws = {{
                      source  = "hashicorp/aws"
                      version = "{aws_provider_version}"
                    }}
                  }}
                }}
                """
            )
        )

    with terraform_apply(
        terraform_module_dir,
        destroy_after=not keep_after,
        json_output=True,
    ) as tf_terraformer_output:
        LOG.info(json.dumps(tf_terraformer_output, indent=4))

        # Extract outputs from Terraform
        instance_id = tf_terraformer_output["instance_id"]["value"]
        cloudwatch_namespace = tf_terraformer_output["cloudwatch_namespace"]["value"]
        log_group_name = tf_terraformer_output["cloudwatch_log_group_name"]["value"]

        # Create EC2Instance object for the terraformer instance
        instance = EC2Instance(instance_id, region=aws_region, role_arn=test_role_arn)

        # Verify CloudWatch integration
        verify_cloudwatch_integration(
            instance=instance,
            boto3_session=boto3_session,
            aws_region=aws_region,
            cloudwatch_namespace=cloudwatch_namespace,
            log_group_name=log_group_name,
        )
