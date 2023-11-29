# hl-component-sftp CfHighlander project
---

## Important considerations

If you want SFTP to be accessed over the internet, you will need to add an ACL rule for port 22 to the VPC config (note you will possibly then need to specify all of the ACL rules or else the default rules will be removed):

```
-
  acl: public
  number: 100
  from: 22
  ips:
    - sftp

ip_blocks:
  sftp:
    - 52.64.86.162/32   # base2 VPN for example
```

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

### `domain`

`S3` - S3 bucket for storage

`EFS` - EFS FileSystem for storage

## EFS

SFTP can be configured to point to an EFS FileSystem, to do so there are a few specific configurations needed to be made and the user setup is slightly different to when the domain is S3.

### `sftp.config.yaml` file

Set the `domain` to EFS:

```
domain: EFS
```

### cfhighlander file

You will need to specify the parameter for the FileSystemId. Example:

```
Component name: 'sftp', template: 'sftp' do
  parameter name: 'VpcId', value: cfout('vpcv2', 'VPCId')
  parameter name: 'SubnetIds', value: cfout('vpcv2', 'PublicSubnets')
  parameter name: 'DnsDomain', value: FnSub("${EnvironmentName}.#{root_domain}")
  parameter name: 'FileSystemId', value: cfout('efsv2', 'FileSystem')
end
```

### Example user config

Here's how to configure a user for EFS, this is in the `sftp.config.yaml` file:

```
users:
  - name: base2
    # home_directory_type and home_directory_mappings go together, as if you want to use logical directories you need mappings, if you just want path directories then don't specify home_directory_type
    home_directory_type: LOGICAL
    home_directory_mappings:
      - entry: /                                    # This is what the directory will be for the user connecting, specify / if you don't have any special requirements
        target: /${FileSystemId}/ftp_home/base2     # This is where the directory will point to on the FileSystem, currently you need to specify /${FileSystemId} to tell it to put it on the root of the FileSystem. Currently you also need to create this directory on the FileSystem yourself
    keys:
      - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDg6Q8ceKXLwe3kKUm7R9gEgekgdSUqD78umhWl11BtlYfGLJc3ZKTzBzANaOLyB1BO+xHw1QPDvK+LrfexLvO5WHQuFI5OtoFaPKZc3clL1PqeEAMvspddIElGtq0lEqMNHdrEryxMFNHd3lcwh45TGPOzY6y5GvOpq/Y5qUnVMfxGtW8G3AQ+Td0yd7swekLz13aUIg9U7aHJdwwukd8e9Hg+YHQrlKyGkq4gccMO8mUFMDaqyruZAhzWneJWJU4TvvK4gsaZHi+uO5e8PB/bIlzhSAlPrghuROgQye4+JanCMlW0QIL9IAF4wWuHmmIXrxxMTIg+4Qqthpav/9iX
    access:
      - read
      - write
    posix:
      Uid: 0000                                     # Iterate the Uid for every new user
      Gid: 1002                                     # Copy the Gid for every user (1002 was the Gid for the sftp group created on the example EFS FileSystem)
      #SecondaryGids:                               # Currently not supported, this would allow users to be members of multiple groups
      #  - 1003
    filesystem: ${FileSystemId}                     # Reference the parameter, this is required for the user's IAM role
```

### EFS future improvements

- Support `SecondaryGids` - just need to figure out the Ruby to pull the values out
- Create a custom resource to create the specified target directory on the FileSystem if it doesn't already exist. Currently this is a manual process, which is less than ideal

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
