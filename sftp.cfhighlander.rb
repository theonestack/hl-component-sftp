CfhighlanderTemplate do

  Parameters do
    ComponentParam 'EnvironmentName', 'dev', isGlobal: true
    ComponentParam 'EnvironmentType', 'development', allowedValues: ['development','production'], isGlobal: true
    ComponentParam 'DnsDomain', ''
    ComponentParam 'EnableTransferServer', 'true', allowedValues: ['true','false']
    ComponentParam 'S3Message', ''
    if endpoint.upcase == 'VPC_ENDPOINT' || endpoint.upcase == 'VPC'
      ComponentParam 'VpcId', type: 'AWS::EC2::VPC::Id'
      ComponentParam 'SubnetIds', type: 'CommaDelimitedList'
    end
    if endpoint.upcase == 'VPC' && vpc_public == true
      ComponentParam 'AvailabilityZones', max_availability_zones, 
        allowedValues: (1..max_availability_zones).to_a,
        description: 'Set the Availabiltiy Zone count for the sftp server',
        isGlobal: true 
      ComponentParam 'EIPs', '', 
        type: 'CommaDelimitedList',
        description: 'List of EIP Ids, if none are provided they will be created'
    end
  end

  LambdaFunctions 'apigateway_identity_provider' if identity_provider.upcase == 'API_GATEWAY'
  LambdaFunctions 'output_vpc_endpoint_ips_custom_resource' if output_vpc_endpoint_ips
  LambdaFunctions 'dynamic_users_create_and_cleanup' if identity_provider.upcase == 'API_GATEWAY' and dynamic_users
end
