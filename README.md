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
