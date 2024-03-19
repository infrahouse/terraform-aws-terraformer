import json
from os import path as osp
from textwrap import dedent

from infrahouse_toolkit.terraform import terraform_apply

from tests.conftest import (
    LOG,
    TRACE_TERRAFORM,
    DESTROY_AFTER,
    TEST_ZONE,
    TEST_ROLE_ARN,
    REGION,
)


def test_module(ec2_client, route53_client, autoscaling_client):
    terraform_root_dir = "test_data"

    terraform_module_dir = osp.join(terraform_root_dir, "service-network")
    # Create service network
    with open(osp.join(terraform_module_dir, "terraform.tfvars"), "w") as fp:
        fp.write(
            dedent(
                f"""
                role_arn = "{TEST_ROLE_ARN}"
                region = "{REGION}"
                """
            )
        )
    with terraform_apply(
        terraform_module_dir,
        destroy_after=DESTROY_AFTER,
        json_output=True,
        enable_trace=TRACE_TERRAFORM,
    ) as tf_service_network_output:
        LOG.info(json.dumps(tf_service_network_output, indent=4))

        subnet_public_ids = tf_service_network_output["subnet_public_ids"]["value"]
        subnet_private_ids = tf_service_network_output["subnet_private_ids"]["value"]
        terraform_module_dir = osp.join(terraform_root_dir, "terraformer")
        # Create terraformer
        with open(osp.join(terraform_module_dir, "terraform.tfvars"), "w") as fp:
            fp.write(
                dedent(
                    f"""
                    role_arn = "{TEST_ROLE_ARN}"
                    region = "{REGION}"
                    zone_name = "{TEST_ZONE}"

                    subnet_public_ids = {json.dumps(subnet_public_ids)}
                    subnet_private_ids = {json.dumps(subnet_private_ids)}
                    """
                )
            )
        with terraform_apply(
            terraform_module_dir,
            destroy_after=DESTROY_AFTER,
            json_output=True,
            enable_trace=TRACE_TERRAFORM,
        ) as tf_terraformer_output:
            LOG.info(json.dumps(tf_terraformer_output, indent=4))
