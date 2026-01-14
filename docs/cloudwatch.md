# CloudWatch Integration

This document covers CloudWatch Logs, Metrics, and Alarms for the Terraformer module.

## CloudWatch Logs

### Log Group

The module creates a dedicated log group:

- **Name:** `/aws/ec2/terraformer`
- **Retention:** Configurable (default: 365 days)
- **Encryption:** Default AWS encryption

```hcl
module "terraformer" {
  # ...
  cloudwatch_log_retention = 365  # ISO compliant
}
```

### What Gets Logged

The terraformer instance can write logs to CloudWatch via the CloudWatch agent (configured by Puppet):

- **System logs:** `/var/log/syslog`, `/var/log/auth.log`
- **Application logs:** Terraform runs, AWS CLI commands
- **Puppet logs:** Puppet agent runs and errors
- **Custom application logs**

### Accessing Logs

=== "AWS Console"

    1. Go to CloudWatch → Log groups
    2. Find `/aws/ec2/terraformer`
    3. Browse log streams (organized by instance ID)

=== "AWS CLI"

    ```bash
    # List log streams
    aws logs describe-log-streams \
      --log-group-name "/aws/ec2/terraformer" \
      --order-by LastEventTime \
      --descending \
      --max-items 10

    # Tail logs
    aws logs tail "/aws/ec2/terraformer" --follow

    # Search for specific pattern
    aws logs filter-log-events \
      --log-group-name "/aws/ec2/terraformer" \
      --filter-pattern "ERROR"
    ```

=== "Terraform Output"

    ```bash
    LOG_GROUP=$(terraform output -raw cloudwatch_log_group_name)
    aws logs tail "$LOG_GROUP" --follow
    ```

### Testing Log Integration

From the terraformer instance, test writing logs:

```bash
# Write test log to CloudWatch
aws logs put-log-events \
  --log-group-name "/aws/ec2/terraformer" \
  --log-stream-name "test-stream" \
  --log-events timestamp=$(date +%s)000,message="Test log message"
```

## CloudWatch Metrics

### Custom Metrics Namespace

The module configures a custom namespace for terraformer metrics using the convention `Service/Component`:

```hcl
module "terraformer" {
  # ...
  cloudwatch_namespace = "Terraformer/System"  # Default
}
```

### Publishing Metrics

From the terraformer instance:

```bash
# Publish a custom metric
aws cloudwatch put-metric-data \
  --namespace "Terraformer/System" \
  --metric-name "TerraformRunDuration" \
  --value 120 \
  --unit Seconds
```

### IAM Permissions

The instance has permission to publish metrics only to its configured namespace:

```json
{
  "Effect": "Allow",
  "Action": "cloudwatch:PutMetricData",
  "Resource": "*",
  "Condition": {
    "StringEquals": {
      "cloudwatch:namespace": "Terraformer/System"
    }
  }
}
```

## CloudWatch Alarms

### Auto-Recovery Alarms

#### System Status Check Alarm

**Purpose:** Detect and recover from hardware failures.

```hcl
resource "aws_cloudwatch_metric_alarm" "terraformer_system_auto_recovery" {
  alarm_name          = "terraformer-system-auto-recovery-${instance_id}"
  alarm_description   = "Auto recover Terraformer instance when underlying hardware fails"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_System"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0.5
  comparison_operator = "GreaterThanOrEqualToThreshold"

  dimensions = {
    InstanceId = aws_instance.terraformer.id
  }

  alarm_actions = ["arn:aws:automate:${region}:ec2:recover"]
}
```

**What it monitors:**

- Host hardware issues
- Network path failures
- Power problems on underlying host

**Action:** Migrates instance to healthy hardware (preserves instance ID, IP, volumes).

#### Instance Status Check Alarm

**Purpose:** Detect and recover from software failures.

```hcl
resource "aws_cloudwatch_metric_alarm" "terraformer_instance_check" {
  alarm_name          = "terraformer-instance-status-check-${instance_id}"
  alarm_description   = "Auto-reboot Terraformer instance on status check failures"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_Instance"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 0.5
  comparison_operator = "GreaterThanOrEqualToThreshold"

  dimensions = {
    InstanceId = aws_instance.terraformer.id
  }

  alarm_actions = ["arn:aws:automate:${region}:ec2:reboot"]
}
```

**What it monitors:**

- Kernel panics
- Out of memory conditions
- Network misconfiguration
- Failed instance checks

**Action:** Reboots the instance.

### CPU Utilization Alarm

The module automatically creates a CPU utilization alarm that sends notifications to the configured `alarm_emails`:

```hcl
module "terraformer" {
  # ...
  alarm_emails = ["ops-team@example.com", "oncall@example.com"]
}
```

!!! warning "Email Confirmation Required"
    AWS SNS sends confirmation emails to each address. Recipients **MUST** click the confirmation link to receive notifications.

**Configuration:**

- **Threshold:** 90% CPU
- **Evaluation:** 1 period of 60 seconds
- **Action:** SNS notification to all confirmed subscribers

## Monitoring Examples

### Create Custom Alarms

For Terraform run failures:

```hcl
resource "aws_cloudwatch_metric_alarm" "terraform_failures" {
  alarm_name          = "terraformer-terraform-failures"
  alarm_description   = "Alert on Terraform apply failures"
  namespace           = "Terraformer/System"
  metric_name         = "TerraformApplyFailures"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  # Use the module's SNS topic output
  alarm_actions = [module.terraformer.sns_topic_arn]
}
```

Then from terraformer instance:

```bash
#!/bin/bash
# terraform-wrapper.sh

terraform apply -auto-approve
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
  # Publish failure metric
  aws cloudwatch put-metric-data \
    --namespace "Terraformer/System" \
    --metric-name "TerraformApplyFailures" \
    --value 1 \
    --unit Count
fi

exit $EXIT_CODE
```

### Monitor Instance Health

Create a dashboard:

```hcl
resource "aws_cloudwatch_dashboard" "terraformer" {
  dashboard_name = "terraformer-health"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/EC2", "CPUUtilization", { stat = "Average", label = "CPU" }],
            [".", "StatusCheckFailed_System", { stat = "Maximum", label = "System Check" }],
            [".", "StatusCheckFailed_Instance", { stat = "Maximum", label = "Instance Check" }]
          ]
          period = 300
          region = var.region
          title  = "Terraformer Health"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      }
    ]
  })
}
```

## Log Insights Queries

### Failed SSH Attempts

```sql
fields @timestamp, @message
| filter @message like /Failed password/
| sort @timestamp desc
| limit 20
```

### Terraform Apply Commands

```sql
fields @timestamp, @message
| filter @message like /terraform apply/
| sort @timestamp desc
```

### Sudo Commands

```sql
fields @timestamp, @message
| filter @message like /sudo:/
| parse @message "* : * : * ; *" as timestamp, user, pwd, command
| display timestamp, user, command
```

### Instance Reboots

```sql
fields @timestamp, @message
| filter @message like /reboot/ or @message like /shutdown/
| sort @timestamp desc
```

## Cost Optimization

### Log Retention

Balance compliance requirements with cost:

```hcl
# ISO 27001: 365 days
cloudwatch_log_retention = 365

# GDPR: 90-180 days typical
cloudwatch_log_retention = 90

# PCI DSS: 90 days minimum
cloudwatch_log_retention = 90
```

**Pricing (us-west-2):**

- Ingestion: $0.50 per GB
- Storage: $0.03 per GB per month
- 365-day retention: ~$0.93 per GB total

### Selective Logging

Configure CloudWatch agent to log only what you need:

```json
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/auth.log",
            "log_group_name": "/aws/ec2/terraformer",
            "log_stream_name": "{instance_id}/auth"
          },
          {
            "file_path": "/var/log/terraform.log",
            "log_group_name": "/aws/ec2/terraformer",
            "log_stream_name": "{instance_id}/terraform"
          }
        ]
      }
    }
  }
}
```

## Troubleshooting

### Logs Not Appearing

1. **Check IAM permissions:**
   ```bash
   aws iam get-role-policy \
     --role-name terraformer-XXXXXXXXXXXX \
     --policy-name terraformer-policy
   ```

2. **Verify CloudWatch agent is running:**
   ```bash
   sudo systemctl status amazon-cloudwatch-agent
   ```

3. **Check agent configuration:**
   ```bash
   sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
     -a fetch-config \
     -m ec2 \
     -s
   ```

### Metrics Not Publishing

1. **Test permissions:**
   ```bash
   aws cloudwatch put-metric-data \
     --namespace "Terraformer/System" \
     --metric-name "TestMetric" \
     --value 1
   ```

2. **Check for errors:**
   ```bash
   # Look for API errors in logs
   sudo journalctl -u amazon-cloudwatch-agent -n 100
   ```

### Alarm Not Triggering

1. **Check alarm state:**
   ```bash
   aws cloudwatch describe-alarms \
     --alarm-names "terraformer-system-auto-recovery-i-xxxxxxxxx"
   ```

2. **View alarm history:**
   ```bash
   aws cloudwatch describe-alarm-history \
     --alarm-name "terraformer-system-auto-recovery-i-xxxxxxxxx" \
     --max-records 10
   ```

3. **Test alarm:**
   ```bash
   # Temporarily lower threshold
   aws cloudwatch put-metric-alarm \
     --alarm-name "terraformer-system-auto-recovery-i-xxxxxxxxx" \
     --threshold 0.1 \
     --evaluation-periods 1
   ```