import boto3
import sys
import logging
import traceback
import json
import cr_response
import random
import string

log = logging.getLogger()
log.setLevel(logging.INFO)

"""
This function input of NetworkInterfaceIds from a VPC Endpoint
and returns the subnet ids of each interface
"""
def handler(event, context):
    log.info(f"Received event:{json.dumps(event)}")

    cr_resp = cr_response.CustomResourceResponse(event)
    params = event['ResourceProperties']
    log.info(f"Resource Properties {params}")

    try:
        if 'NetworkInterfaceIds' not in params:
            raise Exception('Resource must have NetworkInterfaceIds property')

        if event['RequestType'] == 'Create':
            response = lookup_ip(params['NetworkInterfaceIds'])
            event['PhysicalResourceId'] = ''.join(random.choices(string.ascii_letters + string.digits, k=32))
            cr_resp.respond(response)
        elif event['RequestType'] == 'Update':
            response = lookup_ip(params['NetworkInterfaceIds'])
            cr_resp.respond(response)
        elif event['RequestType'] == 'Delete':
            cr_resp.respond()
    except Exception as e:
        traceback.print_exc(file=sys.stdout)
        cr_resp.respond_error(str(e))
    return 'OK'

def lookup_ip(eips):
    client = boto3.client('ec2')
    response = client.describe_network_interfaces(
        NetworkInterfaceIds=eips
    )
    ips = []
    for nic in response['NetworkInterfaces']:
        ips.append(nic['PrivateIpAddress'])
    log.info(f"found ips {','.join(ips)}")
    return { 'VpcEndpointIPs': ','.join(ips) }
