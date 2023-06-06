import boto3
import botocore.exceptions
import json
import sys
import os

sys.path.append(f"{os.environ['LAMBDA_TASK_ROOT']}/lib")
sys.path.append(os.path.dirname(os.path.realpath(__file__)))

import cr_response

efs = boto3.client('efs')

def handler(event, context):
    print(f"Received event:{json.dumps(event)}")
    lambda_response = cr_response.CustomResourceResponse(event)
    filesystem_id = event['ResourceProperties']['FileSystemId']
    filesystem_policy = event['ResourceProperties']['Policy']

    try:
        if event['RequestType'] == 'Create':
            if check_filesystem_policy(filesystem_id) == False:
                event['PhysicalResourceId'] = context.log_stream_name     # Set the PhysicalResourceId to the name of the current log stream for the function as there is no physical resource being created
                create_filesystem_policy(filesystem_id, filesystem_policy)
                lambda_response.respond()
            else:
                lambda_response.respond_error("There is already a policy on this FileSystem, overwriting or modifying an existing FileSystem policy is not currently supported.")
        elif event['RequestType'] == 'Update':
            update_filesystem_policy(filesystem_id, filesystem_policy)
            lambda_response.respond()
        elif event['RequestType'] == 'Delete':
            delete_filesystem_policy(filesystem_id)
            lambda_response.respond()
    except Exception as e:
        message = str(e)
        lambda_response.respond_error(message)
    return 'OK'

def create_filesystem_policy(filesystem_id, filesystem_policy):
    print(f"Creating a FileSystem policy for {filesystem_id}")
    try:
        response = efs.put_file_system_policy(
            FileSystemId=filesystem_id,
            Policy=json.dumps(filesystem_policy)
        )
        print(response)
        return response
    except Exception as error:
        print(f"error:{error}\n")
        raise error

def update_filesystem_policy(filesystem_id, filesystem_policy):
    print(f"Updating the FileSystem policy for {filesystem_id}")
    # There is no update FileSystem policy method so we have to delete and create again
    try:
        response = efs.delete_file_system_policy(
            FileSystemId=filesystem_id
        )
        print(response)
        response = efs.put_file_system_policy(
            FileSystemId=filesystem_id,
            Policy=json.dumps(filesystem_policy)
        )
        print(response)
        return response
    except Exception as error:
        print(f"error:{error}\n")
        raise error

def delete_filesystem_policy(filesystem_id):
    print(f"Deleting the FileSystem policy for {filesystem_id}")
    try:
        response = efs.delete_file_system_policy(
            FileSystemId=filesystem_id
        )
        print(response)
        return response
    except Exception as error:
        print(f"error:{error}\n")
        raise error
    
def check_filesystem_policy(filesystem_id):  
    try:
        print("Checking the FileSystem for a FileSystem policy...")
        response = efs.describe_file_system_policy(
            FileSystemId=filesystem_id
        )
        print('Filesystem policy found.')
        return True   
    except botocore.exceptions.ClientError as error:
        if error.response['Error']['Code'] == 'PolicyNotFound':
            print('No FileSystem policy found.')
            return False
        else:
            raise error