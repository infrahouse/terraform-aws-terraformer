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

    # 1. Verify CloudWatch Log Group exists in AWS
    LOG.info("1. Verifying CloudWatch Log Group exists in AWS...")
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

    # 2. Verify end-to-end logging using AWS CLI from instance
    LOG.info("2. Verifying end-to-end CloudWatch Logs integration...")

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

    # 3. Verify end-to-end metrics integration
    LOG.info("3. Verifying end-to-end CloudWatch Metrics integration...")

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


def verify_inspector_exclusion_tagged(instance):
    """
    Verify the instance launched with the InspectorEc2Exclusion tag.

    The tag defers AWS Inspector findings until security updates are applied, so the first
    findings describe an already patched host. Check this before waiting for Puppet: once
    profile::boot_security_upgrade has run, the tag is expected to be gone.

    Args:
        instance: EC2Instance object

    Raises:
        AssertionError if the instance launched without the tag
    """
    LOG.info("Testing InspectorEc2Exclusion tag is set at launch...")

    tags = instance.tags

    assert tags.get("InspectorEc2Exclusion") == "true", (
        f"Instance {instance.instance_id} launched without InspectorEc2Exclusion=true, so "
        f"Inspector will report findings against an unpatched host. Tags: {tags}"
    )

    LOG.info("✓ InspectorEc2Exclusion tag present at launch")


def verify_inspector_exclusion_removed(instance, max_wait=600, poll_interval=15):
    """
    Verify Puppet removes the InspectorEc2Exclusion tag once the instance is patched.

    profile::boot_security_upgrade deletes the tag after applying security updates, which
    needs the ec2:DeleteTags permission granted in iam.tf. A timeout here means either the
    Puppet profile is not in role::terraformer or that IAM statement is missing.

    Args:
        instance: EC2Instance object
        max_wait: Maximum time to wait in seconds (default: 600 = 10 minutes)
        poll_interval: Time between checks in seconds (default: 15, above the 10 second
            TTL of the instance describe cache)

    Raises:
        AssertionError if the tag is still present after max_wait
    """
    LOG.info("Waiting for Puppet to remove the InspectorEc2Exclusion tag...")

    for attempt in range(max_wait // poll_interval):
        if "InspectorEc2Exclusion" not in instance.tags:
            LOG.info(
                f"✓ InspectorEc2Exclusion tag removed (after {(attempt + 1) * poll_interval} seconds)"
            )
            return

        LOG.info(
            f"   Tag still present (attempt {attempt + 1}/{max_wait // poll_interval})..."
        )
        time.sleep(poll_interval)

    assert False, (
        f"Puppet did not remove the InspectorEc2Exclusion tag from {instance.instance_id} "
        f"after {max_wait} seconds. Check that role::terraformer includes "
        f"profile::boot_security_upgrade and that ec2:DeleteTags is granted."
    )


def verify_ec2_describe_tags(instance, aws_region):
    """
    Verify the instance has ec2:DescribeTags permission.

    This is required for CloudWatch agent's ec2tagger to work properly.
    """
    LOG.info("Testing ec2:DescribeTags permission...")

    exit_code, stdout, stderr = instance.execute_command(
        f"aws ec2 describe-tags --region {aws_region} --max-items 1"
    )

    if exit_code != 0:
        LOG.error(f"ec2:DescribeTags failed. stderr: {stderr}")

    assert exit_code == 0, (
        f"ec2:DescribeTags permission missing. "
        f"CloudWatch agent ec2tagger requires this permission. "
        f"stderr: {stderr}"
    )

    LOG.info("✓ ec2:DescribeTags permission verified")


@pytest.mark.parametrize("aws_provider_version", ["~> 6.0"], ids=["aws-6"])
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
        fp.write(dedent(f"""
                region = "{aws_region}"
                test_zone_id = "{subzone["subzone_id"]["value"]}"

                subnet_public_ids = {json.dumps(subnet_public_ids)}
                subnet_private_ids = {json.dumps(subnet_private_ids)}
                """))
        if test_role_arn:
            fp.write(dedent(f"""
                    role_arn = "{test_role_arn}"
                    """))

    with open(osp.join(terraform_module_dir, "terraform.tf"), "w") as fp:
        fp.write(dedent(f"""
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
                """))

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

        # Verify the instance launched tagged, before Puppet can remove the tag
        verify_inspector_exclusion_tagged(instance=instance)

        # cloud-init reports done only after ih-bootstrap, and therefore
        # `ih-puppet apply`, succeeded
        instance.wait_for_bootstrap()

        # Verify Puppet removed the exclusion tag once security updates were applied
        verify_inspector_exclusion_removed(instance=instance)

        # Verify CloudWatch integration
        verify_cloudwatch_integration(
            instance=instance,
            boto3_session=boto3_session,
            aws_region=aws_region,
            cloudwatch_namespace=cloudwatch_namespace,
            log_group_name=log_group_name,
        )
        # Verify ec2:DescribeTags permission (required for CloudWatch agent ec2tagger)
        verify_ec2_describe_tags(instance=instance, aws_region=aws_region)
