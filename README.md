# hl-component-sftp CfHighlander project
---

## Config file options

### `dynamic_users`

If set to `true` then the stack will also create an SNS topic that takes a payload like:

```
{
  "username": "username",
  "bucket": "s3-bucket-name",
  "TTL": 7,
  "home": "/home/subfolder",
  "access": ["put", "delete", "mkdir"],
  "keys": ['ssh-AAAA', 'ssh-BBBB']
}
```

`username`, `bucket`, and `TTL` are required, the rest are optional

This SNS topic will then trigger a lambda which will automatically handle the creation of the temporary sftp user

A scheduled daily clean up lambda will automatically delete the temporary sftp user after the specified TTL

### `endpoint`

`PUBLIC` - public SFTP endpoint

`VPC` - allows you to attach a security group to the SFTP endpoint to restrict access. Must specify a public subnet (i.e. with an internet gateway route)

`VPC_ENDPOINT` - old way of doing things, it is recommended that you use the `VPC` option instead

## Cfhighlander Setup

install cfhighlander [gem](https://github.com/theonestack/cfhighlander)

```bash
gem install cfhighlander
```

or via docker

```bash
docker pull theonestack/cfhighlander
```

compiling the templates

```bash
cfcompile sftp
```

compiling with the vaildate fag to validate the templates

```bash
cfcompile sftp --validate
```

publish the templates to s3

```bash
cfpublish sftp --version latest
```

## Using an S3 file for the message content

You need to change the IAM policy given to the CreateDynamicSftpUser script, by adding the following into sftp.config.yaml
```
dynamic_users_create_and_cleanup: 
  custom_policies:
    s3get:
      action:
        - s3:GetObject
      resource: 'arn:aws:s3:::BUCKET-NAME/message.html'
    createuser-iam:
      action:
        - iam:GetRole
        - iam:CreateRole
        - iam:AttachRolePolicy
        - iam:PutRolePolicy
        - iam:CreatePolicy*
      resource:
        - Fn::Sub: arn:aws:iam::${AWS::AccountId}:role/*
        - Fn::Sub: arn:aws:iam::${AWS::AccountId}:policy/*
    createuser-secretsmanager:
      action:
        - secretsmanager:GetSecretValue
        - secretsmanager:DescribeSecret
        - secretsmanager:RestoreSecret
        - secretsmanager:PutSecretValue
        - secretsmanager:CreateSecret
      resource:
        Fn::Sub: arn:aws:secretsmanager:${AWS::Region}:${AWS::AccountId}:secret:*
    createuser-getrandompassword:
      action: secretsmanager:GetRandomPassword
    createuser-snspublish:
      action: sns:Publish
      resource:
        Ref: DynamicSftpUserCreatedTopic
    cleanupusers-iam:
      action:
        - iam:DeleteRolePolicy
        - iam:DeleteRole
        - iam:ListRolePolicies
      resource:
        Fn::Sub: arn:aws:iam::${AWS::AccountId}:role/*SftpAccessRole
    cleanupusers-secretsmanager:
      action:
        - secretsmanager:GetSecretValue
        - secretsmanager:DeleteSecret
      resource: 
        Fn::Sub: arn:aws:secretsmanager:${AWS::Region}:${AWS::AccountId}:secret:sftp/${EnvironmentName}/*
    cleanupusers-listsecrets:
      action: secretsmanager:ListSecrets
  roles:
    CreateDynamicSftpUser:
      policies_inline:
        - cloudwatch-logs
        - createuser-iam
        - createuser-secretsmanager
        - createuser-getrandompassword
        - createuser-snspublish
        - s3get
    CleanupDynamicSftpUsers:
      policies_inline:
        - cloudwatch-logs
        - cleanupusers-iam
        - cleanupusers-secretsmanager
        - cleanupusers-listsecrets

```

Then add the following parameter when calling the SFTP component:

```
CfhighlanderTemplate do
  Component name: 'sftp', template: 'sftp', conditional: true do
    parameter name: 'BucketName', value: cfout('s3.Snapshot')
    parameter name: 'S3Message', value: 'BUCKET-NAME/message.html'
  end
  Component 's3'
  Component 's3-cleanup-on-delete', dependson: ['s3'] do
    parameter name: 'Buckets', value: cfout('s3.Snapshot')
  end
end
```