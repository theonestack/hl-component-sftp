CloudFormation do

  Condition('IfDns', FnNot(FnEquals(Ref('DnsDomain'), '')))

  default_tags = []
  default_tags << { Key: "EnvironmentName", Value: Ref("EnvironmentName") }
  default_tags << { Key: "EnvironmentType", Value: Ref("EnvironmentType") }

  tags.each do |key, value|
    default_tags << { Key: key, Value: value }
  end if defined? tags

  # Create the resources required for the apigateway identity providor
  if identity_provider.upcase == 'API_GATEWAY'

    ApiGateway_RestApi(:CustomIdentityProviderApi) {
      Name FnSub("${EnvironmentName}-sftp-custom-identity-providor")
      FailOnWarnings true
      EndpointConfiguration({
        Types: ['REGIONAL']
      })
    }

    IAM_Role(:TransferIdentityProviderRole) {
      AssumeRolePolicyDocument service_role_assume_policy('transfer')
      Path '/'
      Policies ([
        PolicyName: 'transfer-identity',
        PolicyDocument: {
          Statement: [
            {
              Effect: "Allow",
              Action: [
                "apigateway:GET"
              ],
              Resource: "*"
            },
            {
              Effect: "Allow",
              Action: [
                "execute-api:Invoke"
              ],
              Resource: FnSub("arn:aws:execute-api:${AWS::Region}:${AWS::AccountId}:${CustomIdentityProviderApi}/${EnvironmentName}/GET/*")
            }
          ]
      }])
    }

    IAM_Role(:ApiGatewayLoggingRole) {
      AssumeRolePolicyDocument service_role_assume_policy('apigateway')
      Path '/'
      Policies ([
        PolicyName: 'logging',
        PolicyDocument: {
          Statement: [
            {
              Effect: "Allow",
              Action: [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams",
                "logs:PutLogEvents",
                "logs:GetLogEvents",
                "logs:FilterLogEvents"
              ],
              Resource: "*"
            }
          ]
      }])
    }

    ApiGateway_Account(:ApiLoggingAccount) {
      CloudWatchRoleArn FnGetAtt(:ApiGatewayLoggingRole, :Arn)
    }

    Logs_LogGroup(:ApiAccessLogGroup) {
      LogGroupName FnSub("/#{server_name}/${EnvironmentName}/ApiAccess")
      RetentionInDays 14
    }

    ApiGateway_Stage(:ApiStage) {
      StageName Ref('EnvironmentName')
      DeploymentId Ref(:ApiDeployment)
      MethodSettings([
          {
            DataTraceEnabled: true,
            HttpMethod: "*",
            LoggingLevel: 'INFO',
            ResourcePath: "/*"
          }
      ])
      RestApiId Ref(:CustomIdentityProviderApi)
      AccessLogSetting({
        DestinationArn: FnGetAtt(:ApiAccessLogGroup, :Arn),
        Format: { "requestId":"$context.requestId",
          ip: "$context.identity.sourceIp",
          caller: "$context.identity.caller",
          user: "$context.identity.user",
          requestTime: "$context.requestTime",
          httpMethod: "$context.httpMethod",
          resourcePath: "$context.resourcePath",
          status: "$context.status",
          protocol: "$context.protocol",
          responseLength: "$context.responseLength"
        }.to_json
      })
    }

    ApiGateway_Deployment(:ApiDeployment) {
      DependsOn ["GetUserConfigRequest"]
      RestApiId Ref('CustomIdentityProviderApi')
      StageName FnSub('${EnvironmentName}-deployment')
    }

    Lambda_Permission(:SftpIdentityProvidorLambdaPermission) {
      Action 'lambda:invokeFunction'
      FunctionName Ref('SftpIdentityProvidor')
      Principal 'apigateway.amazonaws.com'
      SourceArn FnSub("arn:aws:execute-api:${AWS::Region}:${AWS::AccountId}:${CustomIdentityProviderApi}/*")
    }

    ApiGateway_Resource(:ServersResource) {
      RestApiId Ref(:CustomIdentityProviderApi)
      ParentId FnGetAtt(:CustomIdentityProviderApi, :RootResourceId)
      PathPart 'servers'
    }

    ApiGateway_Resource(:ServerIdResource) {
      RestApiId Ref(:CustomIdentityProviderApi)
      ParentId Ref(:ServersResource)
      PathPart "{serverId}"
    }

    ApiGateway_Resource(:UsersResource) {
      RestApiId Ref(:CustomIdentityProviderApi)
      ParentId Ref(:ServerIdResource)
      PathPart 'users'
    }

    ApiGateway_Resource(:UserNameResource) {
      RestApiId Ref(:CustomIdentityProviderApi)
      ParentId Ref(:UsersResource)
      PathPart "{username}"
    }

    ApiGateway_Resource(:GetUserConfigResource) {
      RestApiId Ref(:CustomIdentityProviderApi)
      ParentId Ref(:UserNameResource)
      PathPart "config"
    }

    ApiGateway_Method(:GetUserConfigRequest) {
      AuthorizationType 'AWS_IAM'
      HttpMethod 'GET'
      Integration({
        Type: 'AWS',
        IntegrationHttpMethod: 'POST',
        Uri: FnJoin('',['arn:aws:apigateway:', Ref('AWS::Region'), ':lambda:path/2015-03-31/functions/', FnGetAtt(:SftpIdentityProvidor, :Arn), '/invocations']),
        IntegrationResponses: [
          { StatusCode: 200 }
        ],
        RequestTemplates: {
          "application/json": {
            username: "$input.params('username')",
            password: "$input.params('Password')",
            serverId: "$input.params('serverId')"
          }.to_json
        }
      })
      RequestParameters({
        "method.request.header.Password": false
      })
      ResourceId Ref(:GetUserConfigResource)
      RestApiId Ref(:CustomIdentityProviderApi)
      MethodResponses([{
        StatusCode: 200,
        ResponseModels: {
          "application/json": Ref(:GetUserConfigResponseModel)
        }
      }])
    }

    ApiGateway_Model(:GetUserConfigResponseModel) {
      Description "API response for GetUserConfig"
      RestApiId Ref(:CustomIdentityProviderApi)
      ContentType "application/json"
      Schema({
        "$schema": "http://json-schema.org/draft-04/schema#",
        title: "UserUserConfig",
        type: "object",
        properties: {
          HomeDirectory: { type: "string" },
          Role: { type: "string" },
          Policy: { type: "string" },
          PublicKeys: {
            type: "array",
            items:{ type: "string" }
          }
        }
      })
    }
  end

  if endpoint.upcase == 'VPC_ENDPOINT'

    ingress = []
    ip_whitelisting.each do |wl|
      ingress << {
        CidrIp: FnSub(wl['ip']),
        Description: FnSub(wl['desc']),
        FromPort: 22,
        IpProtocol: 'TCP',
        ToPort: 22
      }
    end if ip_whitelisting.any?

    sg_tags = default_tags.map(&:clone)
    sg_tags << { Key: "Name", Value: FnSub("#{server_name}-${EnvironmentName}-sftp-access") }

    EC2_SecurityGroup(:SftpSecurityGroup) {
      VpcId Ref(:VpcId)
      GroupDescription FnSub("Controll sftp access to the #{server_name}-${EnvironmentName} aws transfer server vpc endpoint")
      SecurityGroupIngress ingress if ingress.any?
      SecurityGroupEgress ([
        {
          CidrIp: "0.0.0.0/0",
          Description: "outbound all for port 22",
          FromPort: 22,
          IpProtocol: 'TCP',
          ToPort: 22
        },
        {
          CidrIp: "0.0.0.0/0",
          Description: "outbound all for port ephemeral ports",
          FromPort: 1024,
          IpProtocol: 'TCP',
          ToPort: 65535
        }
      ])
      Tags sg_tags
    }

    EC2_VPCEndpoint(:SftpVpcEndpoint) {
      VpcId Ref(:VpcId)
      ServiceName FnSub("com.amazonaws.${AWS::Region}.transfer.server")
      VpcEndpointType "Interface"
      PrivateDnsEnabled true
      SubnetIds Ref(:SubnetIds)
      SecurityGroupIds [
        Ref(:SftpSecurityGroup)
      ]
    }

    if output_vpc_endpoint_ips
      Resource(:GetVpcEndpointIPs) {
        Type 'Custom::SftpServer'
        Property 'ServiceToken', FnGetAtt(:GetVpcEndpointIPsCR, :Arn)
        Property 'NetworkInterfaceIds', FnGetAtt(:SftpVpcEndpoint, :NetworkInterfaceIds)
      }

      Output(:VpcEndpointIPs) { Value(FnGetAtt(:GetVpcEndpointIPs, :VpcEndpointIPs)) }
    end

  end

  IAM_Role(:SftpServerLoggingRole) {
    AssumeRolePolicyDocument service_role_assume_policy('transfer')
    Path '/'
    Policies ([
      PolicyName: 'logging',
      PolicyDocument: {
        Statement: [
          {
            Effect: "Allow",
            Action: [
              "logs:CreateLogStream",
              "logs:DescribeLogStreams",
              "logs:CreateLogGroup",
              "logs:PutLogEvents"
            ],
            Resource: "*"
          }
        ]
    }])
  }

  sftp_tags = default_tags.map(&:clone)
  sftp_tags << { Key: "Name", Value: FnSub("#{server_name}-${EnvironmentName}") }

  Resource(:SftpServer) {
    Type 'AWS::Transfer::Server'

    Property 'EndpointType', endpoint.upcase
    if endpoint.upcase == 'VPC_ENDPOINT'
      Property 'EndpointDetails', {
        VpcEndpointId: Ref(:SftpVpcEndpoint)
      }
    end

    Property 'IdentityProviderType', identity_provider.upcase
    if identity_provider.upcase == 'API_GATEWAY'
      Property 'IdentityProviderDetails', {
        InvocationRole: FnGetAtt(:TransferIdentityProviderRole, :Arn),
        Url: FnSub("https://${CustomIdentityProviderApi}.execute-api.${AWS::Region}.amazonaws.com/${ApiStage}")
      }
      sftp_tags << { Key: 'IdentityProvidorUrl', Value: FnSub("https://${CustomIdentityProviderApi}.execute-api.${AWS::Region}.amazonaws.com/${ApiStage}") }
    end

    Property 'LoggingRole', FnGetAtt('SftpServerLoggingRole','Arn')
    Property 'Tags', sftp_tags
  }

  users.each do |user|

    user_tags = default_tags.map(&:clone)
    user_tags << { Key: "Name", Value: "#{user['name']}" }

    IAM_Role("#{user['name']}SftpAccessRole") {
      AssumeRolePolicyDocument service_role_assume_policy('transfer')
      Path '/'
      Policies ([
        PolicyName: "sftp-access-for-#{user['name']}",
        PolicyDocument: {
          Statement: [
            {
              Sid: "AllowListingOfUserFolder",
              Effect: "Allow",
              Action: [
                "s3:ListBucket",
                "s3:GetBucketLocation"
              ],
              Resource: FnSub("arn:aws:s3:::#{user['bucket']}")
            },
            {
              Sid: "HomeDirObjectAccess",
              Effect: "Allow",
              Action: [
                  "s3:PutObject",
                  "s3:GetObject",
                  "s3:DeleteObjectVersion",
                  "s3:DeleteObject",
                  "s3:GetObjectVersion"
              ],
              Resource: FnSub("arn:aws:s3:::#{user['bucket']}/*")
            }
          ]
        }
      ])
    }

    user_policy = { Version: "2012-10-17", Statement: [] }

    user_policy[:Statement] << {
      Sid: "AllowListingOfUserFolder",
      Action: [ "s3:ListBucket" ],
      Effect: "Allow",
      Resource: [ "arn:aws:s3:::${!transfer:HomeBucket}" ],
      Condition: {
        StringLike: {
          "s3:prefix" => [
            "${!transfer:HomeFolder}/*",
            "${!transfer:HomeFolder}"
          ]
        }
      }
    }

    user_policy[:Statement] << {
      Sid: "AWSTransferRequirements",
      Effect: "Allow",
      Action: [
        "s3:ListAllMyBuckets",
        "s3:GetBucketLocation"
      ],
      Resource: "*"
    }

    user_policy[:Statement] << {
      Sid: "HomeDirObjectGetAccess",
      Effect: "Allow",
      Action: [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:GetObjectACL"
      ],
      Resource: "arn:aws:s3:::${!transfer:HomeDirectory}*"
    }

    if user.has_key? 'access' and user['access'].include? 'put'
      user_policy[:Statement] << {
        Sid: "HomeDirObjectPutAccess",
        Effect: "Allow",
        Action: [
          "s3:PutObject",
          "s3:PutObjectACL"
        ],
        Resource: "arn:aws:s3:::${!transfer:HomeDirectory}*"
      }
    end

    if user.has_key? 'access' and user['access'].include? 'delete'
      user_policy[:Statement] << {
        Sid: "HomeDirObjectDeleteAccess",
        Effect: "Allow",
        Action: [
          "s3:DeleteObjectVersion",
          "s3:DeleteObject"
        ],
        Resource: "arn:aws:s3:::${!transfer:HomeDirectory}*"
      }
    end

    unless user.has_key? 'access' and user['access'].include? 'mkdir'
      user_policy[:Statement] << {
        Sid: "HomeDirObjectDenyMkdirAccess",
        Effect: "Deny",
        Action: [
          "s3:PutObject"
        ],
        Resource: "arn:aws:s3:::${!transfer:HomeBucket}/*/"
      }
    end

    if identity_provider.upcase == 'API_GATEWAY'

      secret_string = { Role: "${Role}" }
      secret_string[:HomeDirectory] = user.has_key?('home') ? "/#{user['bucket']}#{user['home']}" : "/#{user['bucket']}/home/#{user['name']}"
      secret_string[:Policy] = user_policy.to_json

      if user.has_key? 'keys' and user['keys'].any?
        secret_string[:PublicKeys] = user['keys']
      end

      SecretsManager_Secret("#{user['name']}SftpUserSecret") {
        Name FnSub("sftp/${EnvironmentName}/#{user['name']}")
        Description FnSub("${EnvironmentName} sftp user deatils for #{user['name']}")
        GenerateSecretString ({
          SecretStringTemplate: FnSub(secret_string.to_json, { Role: FnGetAtt("#{user['name']}SftpAccessRole", :Arn) }),
          GenerateStringKey: "Password",
          PasswordLength: 32,
          ExcludeCharacters: "@/\\\""
        })
      }

    else

      Resource("#{user['name']}SftpUser") {
        Type 'AWS::Transfer::User'
        Property 'HomeDirectory', user['home'] if user.has_key? 'home'
        Property 'UserName', user['name']
        Property 'ServerId', Ref(:SftpServer)
        Property 'Role', FnGetAtt("#{user['name']}SftpAccessRole", :Arn)
        Property 'Policy', user_policy.to_json

        if user.has_key? 'keys' and user['keys'].any?
          Property 'SshPublicKeys', user['keys']
        end

        Property 'Tags', user_tags
      }
    end

  end if defined? users

  Route53_RecordSet(:SftpServerRecord) {
    Condition('IfDns')
    HostedZoneName FnSub("#{dns_format}.")
    Name FnSub("#{server_name}.#{dns_format}.")
    Type 'CNAME'
    TTL '60'
    Comment FnJoin("", [Ref('EnvironmentName') ," sftp server ", FnGetAtt(:SftpServer,:ServerId)])
    ResourceRecords [ FnJoin('.',[ FnGetAtt(:SftpServer, :ServerId), 'server.transfer', Ref('AWS::Region'), 'amazonaws.com' ]) ]
  }

  Output(:SftpServerId) { Value(FnGetAtt(:SftpServer, :ServerId)) }
  Output(:SftpServerEndpoint) { Value(FnJoin('.',[ FnGetAtt(:SftpServer, :ServerId), 'server.transfer', Ref('AWS::Region'), 'amazonaws.com' ])) }

end
