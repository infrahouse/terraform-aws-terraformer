#!/usr/bin/env python3
"""
Generate architecture diagram for terraform-aws-terraformer module.

Requirements:
    1. Install Graphviz:
       - macOS: brew install graphviz
       - Linux: apt-get install graphviz
       - Windows: choco install graphviz

    2. Install Python package:
       pip install diagrams

Usage:
    python architecture.py

Output:
    architecture.png (in current directory)
"""

from diagrams import Diagram, Cluster, Edge
from diagrams.aws.compute import EC2
from diagrams.aws.management import Cloudwatch
from diagrams.aws.security import SecretsManager, IAM
from diagrams.aws.network import VPC, Route53

# Match MkDocs Material theme fonts (Roboto)
graph_attr = {
    "splines": "ortho",
    "nodesep": "1.0",
    "ranksep": "1.2",
    "fontsize": "20",
    "fontname": "Roboto",
    "dpi": "150",
    "pad": "0.5",
}

node_attr = {
    "fontname": "Roboto",
    "fontsize": "14",
    "width": "1.8",
    "height": "1.8",
}

edge_attr = {
    "fontname": "Roboto",
    "fontsize": "12",
}

with Diagram(
    "Terraformer Module",
    filename="architecture",
    show=False,
    direction="LR",
    graph_attr=graph_attr,
    node_attr=node_attr,
    edge_attr=edge_attr,
    outformat="png",
):
    # Target accounts (what terraformer manages)
    with Cluster("Target AWS Accounts"):
        targets = [
            IAM("\nAccount A"),
            IAM("\nAccount B"),
            IAM("\nAccount C"),
        ]

    with Cluster("Source AWS Account"):
        # DNS
        dns = Route53("\nRoute53\nA Record")

        # Secrets
        ssh_key = SecretsManager("\nSSH Key")

        # IAM
        with Cluster("IAM"):
            role = IAM("\nInstance Role")

        # VPC Resources
        with Cluster("VPC / Private Subnet"):
            ec2 = EC2("\nTerraformer\nEC2 Instance")
            sg = VPC("\nSecurity Group")

        # CloudWatch
        with Cluster("CloudWatch"):
            logs = Cloudwatch("\nAudit Logs")
            alarms = Cloudwatch("\nAlarms\n(auto-recovery)")

    # ============ CONNECTIONS ============

    # DNS resolution
    dns >> Edge(style="dashed") >> ec2

    # Security
    sg >> ec2
    ssh_key >> Edge(label="SSH access") >> ec2

    # IAM
    ec2 >> role

    # Monitoring
    ec2 >> logs
    alarms >> Edge(label="recover/reboot", color="orange") >> ec2

    # Cross-account access (the main purpose)
    role >> Edge(label="AssumeRole", color="blue") >> targets[0]
    role >> Edge(color="blue") >> targets[1]
    role >> Edge(color="blue") >> targets[2]
