import os
import json
import boto3
import base64
from botocore.exceptions import ClientError

def handler(event, context):
    # Begin constructing response
    response_data = {}

    if 'username' not in event or 'serverId' not in event:
        return response_data

    # It is recommended to verify server ID against some value, this template does not verify server ID
    input_server_id = event['serverId']
    input_username = event['username']
    print("Username: {}, ServerId: {}".format(input_username, input_server_id))

    if 'password' in event:
        input_password = event['password']
    else:
        print("No password, checking for SSH public key")
        input_password = ''

    # Lookup user's secret which can contain the password or SSH public keys
    secrets_manager_response = get_secret(f"sftp/{os.environ['ENVIRONMENT_NAME']}/{input_username}")

    if secrets_manager_response != None:
        user_info_secret_dict = json.loads(secrets_manager_response)
    else:
        # There was an error when calling secrets manager, most likely the username doesn't exist
        return response_data

    # If we have an incoming password then we are performing password auth and need to validate it agains the Secrets entry
    if input_password != '':
        # Password Auth Flow - Check if we have a Password Key/Value pair in our Secrets Entry
        if 'Password' in user_info_secret_dict:
            response_password = user_info_secret_dict['Password']
    else:
        print("Unable to authenticate user - No field match in Secret for password")
        return response_data

    # Password Auth Flow - Check for password mismatch
    if response_password != input_password:
        print("Unable to authenticate user - Incoming password does not match stored")
        return response_data
    else:
        # SSH Public Key Auth Flow - The incoming password was empty so we are trying ssh auth and need to return the public key data if we have it
        if 'PublicKey' in user_info_secret_dict:
            response_data['PublicKeys'] = [ user_info_secret_dict['PublicKey'] ]

    # If we've got this far then we've either authenticated the user by password or we're using SSH public key auth and
    # we've begun constructing the data response. Check for each key value pair.
    # These are required so set to empty string if missing
    if 'Role' in user_info_secret_dict:
        response_data['Role'] = user_info_secret_dict['Role']
    else:
        print("No field match for role - Set empty string in response")
        response_data['Role'] = ''

    # These are optional so ignore if not present
    if 'Policy' in user_info_secret_dict:
        response_data['Policy'] = user_info_secret_dict['Policy']

    if 'HomeDirectory' in user_info_secret_dict:
        response_data['HomeDirectory'] = user_info_secret_dict['HomeDirectory']

    return response_data

# This function calls out to Secrets Manager to lookup user and returns None if there is an error.
def get_secret(secret_name):
    # Create a Secrets Manager client
    client = boto3.session.Session().client(
        service_name='secretsmanager',
        region_name=os.environ['AWS_REGION']
    )

    try:
        get_secret_value_response = client.get_secret_value(
            SecretId=secret_name
        )
        # Decrypts secret using the associated KMS CMK.
        # Depending on whether the secret is a string or binary, one of these fields will be populated.
        if 'SecretString' in get_secret_value_response:
            secret = get_secret_value_response['SecretString']
            return secret
        else:
            decoded_binary_secret = base64.b64decode(get_secret_value_response['SecretBinary'])
            return decoded_binary_secret
    except ClientError as e:
        print('Error Talking to SecretsManager: ' + e.response['Error']['Code'])
        return None
