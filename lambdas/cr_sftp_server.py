import sys
import os
import boto3
import logging
import time
import traceback

log = logging.getLogger()
log.setLevel(logging.INFO)

sys.path.append(f"{os.environ['LAMBDA_TASK_ROOT']}/lib")
sys.path.append(os.path.dirname(os.path.realpath(__file__)))

import json
import cr_response


def handler(event, context):
    log.info(f"Received event:{json.dumps(event)}")

    cr_resp = cr_response.CustomResourceResponse(event)
    params = event['ResourceProperties']
    print(f"Resource Properties {params}")

    try:
        if 'Region' not in params:
            raise Exception('Resource must have a Region')
        region = params['Region']

        if 'LoggingRole' not in params:
            raise Exception('Resource must have a LoggingRole')
        
        if 'Tags' not in params:
            params['Tags'] = []

        if event['RequestType'] == 'Create':
            sftp_server = create_sftp_server(params, region)
            event['PhysicalResourceId'] = sftp_server['ServerId']
            _wait_till_online(context,sftp_server,region)
            cr_resp.respond(sftp_server)
        elif event['RequestType'] == 'Update':
            sftp_server = update_sftp_server(event['PhysicalResourceId'], params, region)
            cr_resp.respond(sftp_server)
        elif event['RequestType'] == 'Delete':
            delete_sftp_server(event['PhysicalResourceId'],region)
            cr_resp.respond()    
    except Exception as e:
        traceback.print_exc(file=sys.stdout)
        cr_resp.respond_error(str(e))
    return 'OK'

def create_sftp_server(params, region):
    sftp = boto3.client('transfer', region_name=region)
    response = sftp.create_server(
        IdentityProviderType='SERVICE_MANAGED',
        LoggingRole=params['LoggingRole'],
        Tags=params['Tags']
    )
    sftp_server = _get_server_details(response['ServerId'],region)
    return sftp_server

def update_sftp_server(server_id, params, region):
    sftp = boto3.client('transfer', region_name=region)
    response = sftp.update_server(
        LoggingRole=params['LoggingRole'],
        ServerId=server_id
    )
    return _get_server_details(response['ServerId'],region)

def delete_sftp_server(server_id,region):
    sftp = boto3.client('transfer', region_name=region)
    sftp.delete_server(ServerId=server_id)

def _get_server_details(server_id,region):
    sftp = boto3.client('transfer', region_name=region)
    response = sftp.describe_server(ServerId=server_id)
    response['Server']['StpServerEndpoint'] = f"{server_id}.server.transfer.{region}.amazonaws.com"
    return response['Server']

def _wait_till_online(context, sftp_server, region):
    max_wait_secs = (context.get_remaining_time_in_millis() / 1000) - 20
    wait_interval_secs=10
    start = time.time()
    server_state = sftp_server['State']
    while server_state != 'ONLINE':
        server_state = _get_server_details(sftp_server['ServerId'],region)['State']
        if server_state != 'ONLINE':
            wait_secs = time.time() - start
            log.info(f"Max wait: {max_wait_secs}. Current wait: {wait_secs}")
            if wait_secs >= max_wait_secs:
                raise Exception(f"Timeout Error: SFTP Server {sftp_server['ServerId']} did not come online in {max_wait_secs} seconds")
            sleep_time = wait_interval_secs
            if wait_interval_secs + wait_secs > max_wait_secs:
                sleep_time = max_wait_secs - wait_secs

            log.info(f"SFTP Server {sftp_server['ServerId']} is not yet ONLINE, waiting {sleep_time} sec..")
            time.sleep(sleep_time)
    log.info(f"SFTP Server {sftp_server['ServerId']} is now ONLINE")
    return