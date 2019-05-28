CfhighlanderTemplate do

  Parameters do
    ComponentParam 'EnvironmentName', 'dev', isGlobal: true
    ComponentParam 'EnvironmentType', 'development', allowedValues: ['development','production'], isGlobal: true
    ComponentParam 'DnsDomain', ''
    if endpoint.upcase == 'VPC_ENDPOINT'
      ComponentParam 'VpcId', type: 'AWS::EC2::VPC::Id'
      ComponentParam 'SubnetIds', type: 'CommaDelimitedList'
    end
  end

  LambdaFunctions 'apigateway_identity_providor' if identity_provider.upcase == 'API_GATEWAY'
  LambdaFunctions 'output_vpc_endpoint_ips_custom_resource' if output_vpc_endpoint_ips
end
