# this code performs the same actions as:
#   https://github.com/theonestack/hl-component-sftp/blob/a176023063d86bfd3e4490832eacb9ba6a2fcecd/sftp.cfndsl.rb#L405-L535
import os
import json
import boto3
from botocore.exceptions import ClientError
import sys
import re
from datetime import timedelta, datetime, timezone

iam = boto3.client('iam')
secretsmanager = boto3.client('secretsmanager')
sns = boto3.client('sns')
s3 = boto3.resource('s3')

def role_exists(role_name: str) -> bool:  
  try:
    iam.get_role(RoleName = role_name)
    return True
  except ClientError as error:
    if error.response['Error']['Code'] == 'NoSuchEntity':
      return False
    else:
      raise Exception(f'Uknown ClientError Error Code when checking if IAM role exists: {error.response["Error"]["Code"]}')
  except:
    print(sys.exc_info()[0])
    raise Exception(f'Uknown exception when checking if IAM role exists, check CloudWatch Logs for more details')


def secret_exists(secret_name: str) -> bool:
  try:
    response = secretsmanager.describe_secret(SecretId = secret_name)
    if 'DeletedDate' in response:
      # secret was scheduled for deletion, restore secret so that we can successfully update the secret later
      secretsmanager.restore_secret(SecretId = secret_name)
    return True
  except ClientError as error:
    if error.response['Error']['Code'] == 'ResourceNotFoundException':
      return False
    else:
      raise Exception(f'Uknown ClientError Error Code when checking if Secrets Manager secret exists: {error.response["Error"]["Code"]}')
  except:
    print(sys.exc_info()[0])
    raise Exception(f'Uknown exception when checking if Secrets Manager secret exists, check CloudWatch Logs for more details')


def handler(event, context):
  msg = json.loads(event['Records'][0]['Sns']['Message'])

  # checking if superset since msg can also include these optional keys: "access" | "home" | "keys"
  if not set(msg.keys()) >= set(['username', 'bucket', 'TTL']):
    raise Exception('Error: JSON payload must include username, bucket, and TTL')

  if not re.search('^[a-zA-Z0-9_][a-zA-Z0-9_-]{2,31}$', msg['username']): # automatically throws error if username is not of type string
    raise Exception(f'username \'{msg["username"]}\' is invalid, must comply with `^[a-zA-Z0-9_][a-zA-Z0-9_-]{{2,31}}$`')


  #####  IAM ROLE CREATE / UPDATE  #####

  role_name = f'{msg["username"]}SftpAccessRole'
  if role_exists(role_name):
    role = iam.get_role(RoleName = role_name)
  else:
    try:
      role = iam.create_role(
        RoleName=role_name,
        AssumeRolePolicyDocument='{"Version": "2012-10-17", "Statement": [{"Effect": "Allow", "Principal": {"Service": "transfer.amazonaws.com"}, "Action": "sts:AssumeRole"}]}',
        Path='/'
      )
    except:
      print(sys.exc_info()[0])
      raise Exception(f'Failed to create IAM role {role_name}')
  
  # set role inline policy regardless if role already exists or not
  try:
    iam.put_role_policy(
      RoleName=role_name,
      PolicyName=f'sftp-access-for-{msg["username"]}',
      PolicyDocument=f'{{"Statement": [{{"Sid": "AllowListingOfUserFolder", "Effect": "Allow", "Action": ["s3:ListBucket", "s3:GetBucketLocation"], "Resource": "arn:aws:s3:::{msg["bucket"]}"}}, {{"Sid": "HomeDirObjectAccess", "Effect": "Allow", "Action": ["s3:PutObject", "s3:GetObject", "s3:DeleteObjectVersion", "s3:DeleteObject", "s3:GetObjectVersion"], "Resource": "arn:aws:s3:::{msg["bucket"]}/*"}}]}}'
    )
  except:
    print(sys.exc_info()[0])
    raise Exception(f'Failed to put inline policy on {msg["username"]}SftpAccessRole')


  #####  SECRETS MANAGER SECRET CREATE / UPDATE  #####

  user_policy = {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "AllowListingOfUserFolder",
        "Action": [ "s3:ListBucket" ],
        "Effect": "Allow",
        "Resource": [ "arn:aws:s3:::${transfer:HomeBucket}" ],
        "Condition": {
          "StringLike": {
            "s3:prefix": [
              "${transfer:HomeFolder}/*",
              "${transfer:HomeFolder}"
            ]
          }
        }
      },
      {
        "Sid": "AWSTransferRequirements",
        "Effect": "Allow",
        "Action": [
          "s3:ListAllMyBuckets",
          "s3:GetBucketLocation"
        ],
        "Resource": "*"
      },
      {
        "Sid": "HomeDirObjectGetAccess",
        "Effect": "Allow",
        "Action": [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetObjectACL"
        ],
        "Resource": "arn:aws:s3:::${transfer:HomeDirectory}*"
      }
    ]
  }
  if 'access' in msg:
    if 'put' in msg['access']:
      user_policy['Statement'].append({
        "Sid": "HomeDirObjectPutAccess",
        "Effect": "Allow",
        "Action": [
          "s3:PutObject",
          "s3:PutObjectACL"
        ],
        "Resource": "arn:aws:s3:::${transfer:HomeDirectory}*"
      })
    if 'delete' in msg['access']:
      user_policy['Statement'].append({
        "Sid": "HomeDirObjectDeleteAccess",
        "Effect": "Allow",
        "Action": [
          "s3:DeleteObjectVersion",
          "s3:DeleteObject"
        ],
        "Resource": "arn:aws:s3:::${transfer:HomeDirectory}*"
      })
  if 'access' not in msg or 'mkdir' not in msg['access']:
    user_policy['Statement'].append({
      "Sid": "HomeDirObjectDenyMkdirAccess",
      "Effect": "Deny",
      "Action": ["s3:PutObject"],
      "Resource": "arn:aws:s3:::${transfer:HomeBucket}/*/"
    })
  
  # no need to make the following code conditional since we are assuming that this function only gets run when identity_provider == API_GATEWAY

  secret_string = { "Role": role['Role']['Arn'] }
  if 'home' in msg:
    secret_string['HomeDirectory'] = f'/{msg["bucket"]}{msg["home"]}'
  else:
    secret_string['HomeDirectory'] = f'/{msg["bucket"]}/home/{msg["username"]}'
  
  secret_string['Policy'] = json.dumps(user_policy, separators=(',', ':'))

  if 'keys' in msg:
    secret_string['PublicKeys'] = msg['keys']
  

  expiry = datetime.now(timezone.utc) + timedelta(days=msg['TTL'])
  secret_string['Expiry'] = expiry.strftime('%Y-%m-%d %H:%M:%S.%f%z')

  environment_name = os.environ['ENVIRONMENT_NAME']
  secret_name = f'sftp/{environment_name}/{msg["username"]}'

  if secret_exists(secret_name):
    # fetch existing password and update secret
    existing_secret = json.loads(secretsmanager.get_secret_value(SecretId = secret_name)['SecretString'])
    if 'Password' in existing_secret:
      secret_string['Password'] = existing_secret['Password']
    else:
      secret_string['Password'] = secretsmanager.get_random_password(ExcludePunctuation=True)['RandomPassword']
    try:
      secretsmanager.put_secret_value(
        SecretId = secret_name,
        SecretString = json.dumps(secret_string)
      )
    except:
      print(sys.exc_info()[0])
      raise Exception(f'Failed to put new secret value for sftp/{environment_name}/{msg["username"]}')
  else:
    secret_string['Password'] = secretsmanager.get_random_password(ExcludePunctuation=True)['RandomPassword']
    try:
      secretsmanager.create_secret(
        Name=secret_name,
        Description=f'{environment_name} sftp user deatils for {msg["username"]}',
        SecretString=json.dumps(secret_string)
      )
    except:
      print(sys.exc_info()[0])
      raise Exception(f'Failed to create secrets manager secret sftp/{environment_name}/{msg["username"]}')

  user_created_sns_topic = os.environ['USER_CREATED_SNS_TOPIC']
  if os.environ['MESSAGE_S3_PATH'] != '':
    s3env = os.environ['MESSAGE_S3_PATH'].replace('s3://','')
    bucketName = s3env.split('/')[0]
    filePath = s3env.split('/')[1]
    object = s3.Object(bucketName, filePath)
    messageContent = object.get()['Body'].read().decode('utf-8')
  else:
    messageContent = f'Temporary sftp user \'{msg["username"]}\' was successfully created. Password is <{secret_string["Password"]}>'
    
  sns.publish(
    TopicArn = user_created_sns_topic,
    Message = messageContent
  )
  return
