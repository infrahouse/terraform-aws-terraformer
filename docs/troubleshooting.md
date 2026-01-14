# Troubleshooting

This document provides solutions to common issues with the Terraformer module.

## Deployment Issues

### Error: environment validation failed

**Problem:**
```
Error: Invalid value for variable
│
│   on variables.tf line 13:
│   13: variable "environment" {
│
│ environment must contain only lowercase letters, numbers, and underscores (no hyphens)
```

**Solution:**

The `environment` variable has strict validation. Ensure it contains only lowercase letters, numbers, and underscores:

```hcl
# ❌ Invalid
environment = "production-us"  # Contains hyphen
environment = "Production"      # Contains uppercase

# ✅ Valid
environment = "production"
environment = "prod_us"
environment = "dev2"
```

### Error: No default value for environment

**Problem:**
```
Error: No value for required variable
│
│ The root module input variable "environment" is not set
```

**Solution:**

This is intentional to prevent deployment mistakes. You must explicitly set the environment:

```hcl
module "terraformer" {
  # ...
  environment = "production"  # Required
}
```

### Error: Circular dependency with CloudWatch log group

**Problem:**
```
Error: Cycle: aws_cloudwatch_log_group.terraformer, module.userdata, aws_instance.terraformer
```

**Solution:**

This was fixed in version 2.0+. The log group now uses a static name `/aws/ec2/terraformer` instead of including the instance ID.

Upgrade to the latest version:

```hcl
module "terraformer" {
  source  = "registry.infrahouse.com/infrahouse/terraformer/aws"
  version = "~> 2.0"  # Use latest
  # ...
}
```

## SNS Notification Issues

### Not receiving alarm notifications

**Problem:**

CloudWatch alarms are triggering but you're not receiving email notifications.

**Solutions:**

1. **Confirm SNS subscription:**

   After deployment, AWS SNS sends a confirmation email to each address in `alarm_emails`. You **must** click the confirmation link in each email to activate notifications.

   Check subscription status:
   ```bash
   # Get SNS topic ARN
   INSTANCE_ID=$(terraform output -raw instance_id)
   TOPIC_ARN=$(aws sns list-topics --query "Topics[?contains(TopicArn, 'terraformer-alarms-${INSTANCE_ID}')].TopicArn" --output text)

   # List subscriptions and their status
   aws sns list-subscriptions-by-topic --topic-arn "$TOPIC_ARN"
   ```

   Look for `SubscriptionArn`. If it shows `PendingConfirmation`, the email was not confirmed.

2. **Resend confirmation email:**

   If you missed or deleted the confirmation email:
   ```bash
   # Delete the pending subscription
   aws sns unsubscribe --subscription-arn <pending-subscription-arn>

   # Re-run Terraform to recreate the subscription
   terraform apply -target=module.terraformer.aws_sns_topic_subscription.alarm_email
   ```

   Check your spam/junk folder for emails from `AWS Notifications <no-reply@sns.amazonaws.com>`.

3. **Verify email address is correct:**

   Check your Terraform configuration:
   ```hcl
   module "terraformer" {
     # ...
     alarm_emails = ["ops-team@example.com"]  # Verify this is correct
   }
   ```

### Confirmation email not received

**Problem:**

You added an email to `alarm_emails` but never received the confirmation email.

**Solutions:**

1. **Check spam/junk folder** — AWS SNS emails often get filtered

2. **Verify email domain accepts AWS emails:**
   - Some corporate email filters block automated emails
   - Contact your email admin to whitelist `no-reply@sns.amazonaws.com`

3. **Check SNS delivery logs:**
   ```bash
   # Enable delivery logging (if not already enabled)
   aws sns set-topic-attributes \
     --topic-arn "$TOPIC_ARN" \
     --attribute-name DeliveryPolicy \
     --attribute-value '{"http":{"defaultHealthyRetryPolicy":{"numRetries":3}}}'
   ```

4. **Try alternative endpoint:**

   If email continues to fail, consider using an SMS or HTTPS endpoint instead.

### Multiple email addresses not all receiving notifications

**Problem:**

You specified multiple emails in `alarm_emails` but only some receive notifications.

**Solution:**

Each email address requires individual confirmation. Check status of all subscriptions:

```bash
aws sns list-subscriptions-by-topic --topic-arn "$TOPIC_ARN" \
  | jq -r '.Subscriptions[] | "\(.Endpoint): \(.SubscriptionArn)"'
```

Any showing `PendingConfirmation` need to be confirmed by clicking the link in the email sent to that address.

## SSH Access Issues

### Cannot connect via SSH

**Problem:**

```bash
$ ssh ubuntu@terraformer.example.com
ssh: connect to host terraformer.example.com port 22: Connection timed out
```

**Solutions:**

1. **Check instance is in private subnet:**
   ```bash
   aws ec2 describe-instances \
     --instance-ids $(terraform output -raw instance_id) \
     --query 'Reservations[0].Instances[0].PublicIpAddress'
   ```

   If it returns an IP, the instance has public access (not recommended). If `null`, it's correctly in a private subnet.

2. **Connect via bastion/VPN:**

   The terraformer is intentionally not publicly accessible. Connect through:
   - Bastion host in public subnet
   - VPN connection to VPC
   - AWS Systems Manager Session Manager

3. **Check security group:**
   ```bash
   aws ec2 describe-security-groups \
     --group-ids $(terraform output -raw security_group_id) \
     --query 'SecurityGroups[0].IpPermissions'
   ```

   Verify SSH (port 22) allows your source IP or VPC CIDR.

### SSH key permission denied

**Problem:**

```bash
$ ssh -i ~/.ssh/terraformer.pem ubuntu@terraformer.example.com
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@         WARNING: UNPROTECTED PRIVATE KEY FILE!          @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
Permissions 0644 for '/home/user/.ssh/terraformer.pem' are too open.
```

**Solution:**

```bash
chmod 600 ~/.ssh/terraformer.pem
```

### Wrong SSH key

**Problem:**

```bash
$ ssh -i ~/.ssh/my-key.pem ubuntu@terraformer.example.com
ubuntu@terraformer.example.com: Permission denied (publickey).
```

**Solution:**

1. **If using auto-generated key:**
   ```bash
   # Get the correct key from Secrets Manager
   SECRET_ARN=$(terraform output -raw ssh_key_secret_arn)
   aws secretsmanager get-secret-value \
     --secret-id "$SECRET_ARN" \
     --query SecretString \
     --output text > ~/.ssh/terraformer.pem
   chmod 600 ~/.ssh/terraformer.pem
   ```

2. **If using custom key:**

   Verify `ssh_key_name` in your configuration matches the key you're using:
   ```hcl
   module "terraformer" {
     # ...
     ssh_key_name = "my-existing-key"  # Must match your key
   }
   ```

## IAM and Permissions Issues

### Error: User is not authorized to perform logs:CreateLogStream

**Problem:**

```
An error occurred (AccessDeniedException) when calling the CreateLogStream operation:
User: arn:aws:sts::123456789012:assumed-role/terraformer-XXXX/i-xxxxxxxxx is not authorized
to perform: logs:CreateLogStream on resource: arn:aws:logs:us-west-2:123456789012:log-group:/aws/ec2/terraformer
```

**Solution:**

This indicates the instance IAM role lacks CloudWatch Logs permissions. This should be automatically granted by the module.

Check if you're using an old version:

```bash
terraform state show module.terraformer.module.profile.aws_iam_role_policy.this
```

Upgrade to version 2.0+ which includes CloudWatch permissions:

```hcl
module "terraformer" {
  source  = "registry.infrahouse.com/infrahouse/terraformer/aws"
  version = "~> 2.0"
  # ...
}

terraform init -upgrade
terraform apply
```

### Cannot assume role in target account

**Problem:**

```bash
$ aws sts assume-role --role-arn arn:aws:iam::TARGET-ACCOUNT:role/admin
An error occurred (AccessDenied) when calling the AssumeRole operation:
User: arn:aws:sts::SOURCE-ACCOUNT:assumed-role/terraformer-XXXX/i-xxxxxxxxx is not authorized
to perform: sts:AssumeRole on resource: arn:aws:iam::TARGET-ACCOUNT:role/admin
```

**Solutions:**

1. **Check trust relationship in target account:**

   The target role must trust the terraformer instance role:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Principal": {
         "AWS": "arn:aws:iam::SOURCE-ACCOUNT:role/terraformer-XXXXXXXXXXXX"
       },
       "Action": "sts:AssumeRole"
     }]
   }
   ```

2. **Get the correct role ARN:**
   ```bash
   terraform output instance_role_arn
   ```

3. **Verify source account has AssumeRole permission:**

   The terraformer role should have this by default, but verify:
   ```bash
   aws iam get-role-policy \
     --role-name $(terraform output -raw instance_role_name) \
     --policy-name terraformer-policy
   ```

## Auto-Recovery Issues

### Instance not recovering from failures

**Problem:**

Instance experienced a failure but didn't auto-recover.

**Solutions:**

1. **Check alarm state:**
   ```bash
   INSTANCE_ID=$(terraform output -raw instance_id)
   aws cloudwatch describe-alarms \
     --alarm-name-prefix "terraformer-" \
     | jq -r '.MetricAlarms[] | select(.Dimensions[0].Value == "'$INSTANCE_ID'")'
   ```

2. **Check alarm history:**
   ```bash
   aws cloudwatch describe-alarm-history \
     --alarm-name "terraformer-system-auto-recovery-$INSTANCE_ID" \
     --max-records 10
   ```

3. **Verify alarm actions are enabled:**
   ```bash
   aws cloudwatch describe-alarms \
     --alarm-names "terraformer-system-auto-recovery-$INSTANCE_ID" \
     --query 'MetricAlarms[0].ActionsEnabled'
   ```

   If `false`, enable:
   ```bash
   aws cloudwatch enable-alarm-actions \
     --alarm-names "terraformer-system-auto-recovery-$INSTANCE_ID"
   ```

### Alarm exists but instance didn't reboot

**Problem:**

Instance status check failed but alarm didn't trigger reboot.

**Solution:**

The alarm requires 3 consecutive failures (3 minutes). Check if the failure was transient:

```bash
# Check instance status check history
aws ec2 describe-instance-status \
  --instance-ids $(terraform output -raw instance_id) \
  --include-all-instances
```

If you need more aggressive recovery, create a custom alarm with lower evaluation periods (not recommended for production).

## CloudWatch Issues

### Logs not appearing in CloudWatch

**Problem:**

Terraformer instance is running but logs aren't appearing in CloudWatch Logs.

**Solutions:**

1. **Check CloudWatch agent status:**
   ```bash
   ssh ubuntu@terraformer.example.com
   sudo systemctl status amazon-cloudwatch-agent
   ```

2. **Verify agent configuration:**
   ```bash
   sudo cat /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
   ```

3. **Check Puppet facts:**
   ```bash
   sudo facter -p terraformer.cloudwatch_log_group
   sudo facter -p terraformer.cloudwatch_namespace
   ```

   Should return `/aws/ec2/terraformer` and `terraformer` respectively.

4. **Restart agent:**
   ```bash
   sudo systemctl restart amazon-cloudwatch-agent
   sudo systemctl status amazon-cloudwatch-agent
   ```

### Cannot publish metrics

**Problem:**

```bash
$ aws cloudwatch put-metric-data --namespace "terraformer" --metric-name "Test" --value 1
An error occurred (AccessDenied) when calling the PutMetricData operation
```

**Solution:**

Verify IAM permissions restrict to correct namespace:

```bash
# This should work
aws cloudwatch put-metric-data \
  --namespace "terraformer" \
  --metric-name "TestMetric" \
  --value 1

# This should fail (different namespace)
aws cloudwatch put-metric-data \
  --namespace "other-namespace" \
  --metric-name "TestMetric" \
  --value 1
```

If both fail, check IAM role policy includes CloudWatch PutMetricData permission.

## Puppet Issues

### Puppet run failures

**Problem:**

Instance launches but Puppet fails to configure it properly.

**Solutions:**

1. **Check Puppet logs:**
   ```bash
   ssh ubuntu@terraformer.example.com
   sudo tail -f /var/log/syslog | grep puppet
   ```

2. **Verify Puppet facts:**
   ```bash
   sudo facter -p | grep -E '(puppet|terraformer)'
   ```

3. **Check marker file:**
   ```bash
   test -f /var/run/puppet-done && echo "Puppet completed" || echo "Puppet still running"
   ```

4. **Manually run Puppet:**
   ```bash
   sudo ih-puppet \
     --environment production \
     --environmentpath /opt/puppet-code/environments \
     --root-directory /opt/puppet-code \
     apply /opt/puppet-code/environments/production/manifests/site.pp
   ```

## DNS Issues

### DNS record not resolving

**Problem:**

```bash
$ nslookup terraformer.example.com
Server:		8.8.8.8
Address:	8.8.8.8#53

** server can't find terraformer.example.com: NXDOMAIN
```

**Solutions:**

1. **Verify Route53 record exists:**
   ```bash
   ZONE_ID=$(terraform output -raw zone_id)
   aws route53 list-resource-record-sets --hosted-zone-id "$ZONE_ID" \
     | jq -r '.ResourceRecordSets[] | select(.Type == "A") | .Name'
   ```

2. **Check DNS name configuration:**
   ```hcl
   module "terraformer" {
     # ...
     dns_name = "terraformer"  # Creates terraformer.example.com
   }
   ```

3. **Verify zone_id is correct:**
   ```bash
   aws route53 get-hosted-zone --id $(terraform output -raw zone_id)
   ```

## State File Issues

### State lock errors

**Problem:**

```
Error: Error acquiring the state lock
```

**Solution:**

If working from terraformer instance and encountering locks:

```bash
# View DynamoDB lock table
aws dynamodb scan --table-name terraform-locks

# Force unlock (use with caution)
terraform force-unlock <LOCK_ID>
```

## Getting Help

If you encounter issues not covered here:

1. **Check module version:**
   ```bash
   terraform state show module.terraformer | grep version
   ```

2. **Enable debug logging:**
   ```bash
   export TF_LOG=DEBUG
   terraform apply
   ```

3. **Review CloudWatch Logs:**
   ```bash
   LOG_GROUP=$(terraform output -raw cloudwatch_log_group_name)
   aws logs tail "$LOG_GROUP" --follow
   ```

4. **Open an issue:**

   [github.com/infrahouse/terraform-aws-terraformer/issues](https://github.com/infrahouse/terraform-aws-terraformer/issues)

Include:
- Terraform version
- Module version
- Error messages
- Relevant Terraform state output
- CloudWatch logs (redacted)