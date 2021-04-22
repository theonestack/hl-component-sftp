import os
import json
import boto3
from botocore.exceptions import ClientError
import sys
from datetime import datetime, timezone

iam = boto3.client('iam')
list_role_policies_paginator = iam.get_paginator('list_role_policies')
secretsmanager = boto3.client('secretsmanager')
list_secrets_iterator = secretsmanager.get_paginator('list_secrets').paginate()

def delete_iam_role(role_name: str):
  list_role_policies_iterator = list_role_policies_paginator.paginate(RoleName=role_name)
  for page in list_role_policies_iterator:
    for inline_policy in page['PolicyNames']:
      try:
        iam.delete_role_policy(RoleName = role_name, PolicyName = inline_policy)
      except ClientError as error:
        print(f'Failed to delete role inline policy \'{inline_policy}\', error: {error.response["Error"]["Code"]}')
        # do not raise Exception so that remaining expired sftp_users can also be deleted
        return
  try:
    iam.delete_role(RoleName = role_name)
  except ClientError as error:
    print(f'Failed to delete role \'{role_name}\', error: {error.response["Error"]["Code"]}')
    # do not raise Exception so that remaining expired sftp_users can also be deleted


def handler(event, context):
  environment_name = os.environ['ENVIRONMENT_NAME']

  # fetch all secrets starting with 'sftp/{EnvironmentName}/'
  sftp_users = []
  for page in list_secrets_iterator:
    for secret in page['SecretList']:
      if secret['Name'].startswith(f'sftp/{environment_name}/'):
        sftp_users.append(secret['Name'])
  
  now = datetime.now(timezone.utc)
  for sftp_user in sftp_users:
    try:
      user_secret = secretsmanager.get_secret_value(SecretId = sftp_user)['SecretString']
    except ClientError as error:
      print(f'Failed to get secret value for \'{sftp_user}\', error: {error.response["Error"]["Code"]}, continuing onto next sftp_user')
      continue

    user_secret = json.loads(user_secret)
    if 'Expiry' in user_secret:
      expiry = datetime.strptime(user_secret['Expiry'], '%Y-%m-%d %H:%M:%S.%f%z')
      if expiry < now:
        print(f'Temporary SFTP user \'{sftp_user}\' has expired, deleting...')
        if 'Role' in user_secret:
          delete_iam_role(user_secret['Role'].split(':role/')[1])
        try:
          secretsmanager.delete_secret(
            SecretId = sftp_user,
            RecoveryWindowInDays = 7
          )
        except ClientError as error:
          print(f'Failed to delete secret \'{sftp_user}\', error: {error.response["Error"]["Code"]}, continuing onto next sftp_user')
