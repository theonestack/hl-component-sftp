CloudFormation do

  Condition(:TransferServerEnabled, FnEquals(Ref(:EnableTransferServer), 'true'))
  Condition(:IfDns, FnAnd([
    FnNot(FnEquals(Ref(:DnsDomain), '')),
    Condition(:TransferServerEnabled)
  ]))
  if identity_provider.upcase == 'API_GATEWAY' && dynamic_users
    Condition(:s3Message, FnNot(FnEquals(Ref(:S3Message), '')))
  end

  default_tags = []
  default_tags << { Key: "Environment", Value: Ref("EnvironmentName") }
  default_tags << { Key: "EnvironmentType", Value: Ref("EnvironmentType") }

  tags = external_parameters.fetch(:tags, {})
  tags.each do |key, value|
    default_tags << { Key: key, Value: value }
  end

  # Create the resources required for the apigateway identity provider
  if identity_provider.upcase == 'API_GATEWAY'

    ApiGateway_RestApi(:CustomIdentityProviderApi) {
      Name FnSub("${EnvironmentName}-sftp-custom-identity-provider")
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

    Lambda_Permission(:SftpIdentityProviderLambdaPermission) {
      Action 'lambda:invokeFunction'
      FunctionName Ref('SftpIdentityProvider')
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
        Uri: FnJoin('',['arn:aws:apigateway:', Ref('AWS::Region'), ':lambda:path/2015-03-31/functions/', FnGetAtt(:SftpIdentityProvider, :Arn), '/invocations']),
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

    if dynamic_users
      SNS_Topic(:CreateDynamicSftpUserTopic) {
        Subscription([{
          Protocol: 'lambda',
          Endpoint: FnGetAtt(:CreateDynamicSftpUser, :Arn)
        }])
      }

      Output(:CreateDynamicSftpUserTopic) {
        Value Ref(:CreateDynamicSftpUserTopic)
        Export FnSub("${EnvironmentName}-#{external_parameters[:component_name]}-create-user-topic")
      }

      SNS_Topic(:DynamicSftpUserCreatedTopic)

      Output(:DynamicSftpUserCreatedTopic) {
        Value Ref(:DynamicSftpUserCreatedTopic)
        Export FnSub("${EnvironmentName}-#{external_parameters[:component_name]}-user-created-topic")
      }
      
      Lambda_Permission(:CreateDynamicSftpUserLambdaPermission) {
        FunctionName FnGetAtt(:CreateDynamicSftpUser, :Arn)
        Action 'lambda:InvokeFunction'
        Principal 'sns.amazonaws.com'
        SourceArn Ref(:CreateDynamicSftpUserTopic)
      }

      Events_Rule(:CleanupUsersDailySchedule) {
        ScheduleExpression 'rate(1 day)'
        Targets([{
          Arn: FnGetAtt(:CleanupDynamicSftpUsers, :Arn),
          Id: 'cleanup-dyanmic-sftp-users-lambda'
        }])
      }

      Lambda_Permission(:CleanupDynamicSftpUsersLambdaPermission) {
        FunctionName FnGetAtt(:CleanupDynamicSftpUsers, :Arn)
        Action 'lambda:InvokeFunction'
        Principal 'events.amazonaws.com'
        SourceArn FnGetAtt(:CleanupUsersDailySchedule, :Arn)
      }
    end

  end

  if endpoint.upcase == 'VPC_ENDPOINT' || endpoint.upcase == 'VPC'
    ingress = []
    ip_whitelisting.each do |wl|
       rule = {
        Description: FnSub(wl['desc']),
        FromPort: 22,
        IpProtocol: 'TCP',
        ToPort: 22
      }

      if wl.has_key?('prefix')
        rule[:SourcePrefixListId] = wl['prefix']
      elsif wl.has_key?('group')
        rule[:SourceSecurityGroupId] = wl['group']
      else
        rule[:CidrIp] = FnSub(wl['ip'])
      end

      ingress << rule
    end if ip_whitelisting.any?

    sg_tags = default_tags.map(&:clone)
    sg_tags << { Key: "Name", Value: FnSub("#{server_name}-${EnvironmentName}-sftp-access") }

    EC2_SecurityGroup(:SftpSecurityGroup) {
      VpcId Ref(:VpcId)
      GroupDescription FnSub("Control sftp access to the #{server_name}-${EnvironmentName} aws transfer server vpc endpoint")
      SecurityGroupIngress ingress if ingress.any?
      Tags sg_tags
      Metadata({
        cfn_nag: {
          rules_to_suppress: [
            { id: 'F1000', reason: 'adding rules using cfn resources' }
          ]
        }
      })
    }
  end

  if endpoint.upcase == 'VPC_ENDPOINT'
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

    if apigateway_endpoint.upcase == 'VPC_ENDPOINT' and identity_provider.upcase == 'API_GATEWAY'

      api_sg_tags = default_tags.map(&:clone)
      api_sg_tags << { Key: "Name", Value: FnSub("${EnvironmentName}-api-gateway-sftp-identity-provider") }

      EC2_SecurityGroup(:ApiGatewaySecurityGroup) {
        VpcId Ref(:VpcId)
        GroupDescription FnSub("Control https access to the ${EnvironmentName} api gateway sftp identity provider vpc endpoint")
        SecurityGroupIngress [{
          SourceSecurityGroupId: Ref(:SftpSecurityGroup),
          Description: "SFTP VPC Endpoint Security Group Id",
          FromPort: 443,
          IpProtocol: 'TCP',
          ToPort: 443
        }]
        Tags api_sg_tags
        Metadata({
          cfn_nag: {
            rules_to_suppress: [
              { id: 'F1000', reason: 'adding rules using cfn resources' }
            ]
          }
        })
      }

      EC2_VPCEndpoint(:ApiGatewayVpcEndpoint) {
        VpcId Ref(:VpcId)
        ServiceName FnSub("com.amazonaws.${AWS::Region}.apigateway")
        VpcEndpointType "Interface"
        PrivateDnsEnabled true
        SubnetIds Ref(:SubnetIds)
        SecurityGroupIds [
          Ref(:ApiGatewaySecurityGroup)
        ]
      }
    end
  
  elsif endpoint.upcase == 'VPC' && vpc_public == true
    Condition(:CreateEIPs, FnEquals(FnJoin("", Ref(:EIPs)), ""))
    
    eip_refs = []

    external_parameters[:max_availability_zones].times do |az|
      get_az = { AZ: FnSelect(az, FnGetAZs(Ref('AWS::Region'))) }
      matches = ((az+1)..external_parameters[:max_availability_zones]).to_a

      Condition("CreateEIP#{az}",
        if matches.length == 1
          FnAnd([
            FnEquals(Ref(:AvailabilityZones), external_parameters[:max_availability_zones]),
            Condition(:CreateEIPs)
          ])
        else
          FnAnd([
            FnOr(matches.map { |i| FnEquals(Ref(:AvailabilityZones), i) }),
            Condition(:CreateEIPs)
          ])
        end
      )

      EC2_EIP("SftpEIP#{az}") {
        Condition "CreateEIP#{az}"
        Domain 'vpc'
        Tags [{Key: 'Name', Value: FnSub("${EnvironmentName}-sftp-${AZ}", get_az) }]
      }

      eip_refs.push(FnGetAtt("SftpEIP#{az}", :AllocationId))
    end

    eip_condition = ''
    external_parameters[:max_availability_zones].times do |az|
      eip_condition = FnIf("CreateEIP#{az}", eip_refs[0..az], eip_condition)
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

  if identity_provider.upcase == 'API_GATEWAY' && dynamic_users
    IAM_Policy(:LambdaRoleCreateDynamicSftpUserS3Policy) {
      Condition(:s3Message)
      PolicyDocument (
        {
          Statement: [
            {
              Effect: "Allow",
              Action: [
                "s3:GetObject"
              ],
              Resource: "*"
            }
          ]
      })
      PolicyName 's3get'
      Roles [Ref('LambdaRoleCreateDynamicSftpUser')]
    }
  end

  sftp_tags = default_tags.map(&:clone)
  sftp_tags << { Key: "Name", Value: FnSub("#{server_name}-${EnvironmentName}") }

  storage_type =  external_parameters.fetch(:storage_type, nil)

  Transfer_Server(:SftpServer) {
    Condition(:TransferServerEnabled)

    EndpointType endpoint.upcase
    Domain domain.upcase

    if endpoint.upcase == 'VPC_ENDPOINT'
      EndpointDetails({
        VpcEndpointId: Ref(:SftpVpcEndpoint)
      })
    elsif endpoint.upcase == 'VPC'
      endpoint_details = {
        SecurityGroupIds: [
          Ref(:SftpSecurityGroup)
        ],
        SubnetIds: Ref(:SubnetIds),
        VpcId: Ref(:VpcId)
      }

      if vpc_public == true
        endpoint_details[:AddressAllocationIds] = FnIf(:CreateEIPs, eip_condition, Ref(:EIPs))
      end
      EndpointDetails(endpoint_details)
    end

    IdentityProviderType identity_provider.upcase

    if identity_provider.upcase == 'API_GATEWAY'
      IdentityProviderDetails({
        InvocationRole: FnGetAtt(:TransferIdentityProviderRole, :Arn),
        Url: FnSub("https://${CustomIdentityProviderApi}.execute-api.${AWS::Region}.amazonaws.com/${ApiStage}")
      })
      sftp_tags << { Key: 'IdentityProviderUrl', Value: FnSub("https://${CustomIdentityProviderApi}.execute-api.${AWS::Region}.amazonaws.com/${ApiStage}") }
    end

    LoggingRole FnGetAtt('SftpServerLoggingRole','Arn')
    Tags sftp_tags
  }

  # Due to circular dependencies and other issues the EFS FileSystem policy is being created in the SFTP stack using a custom resource lambda function called efs_filesystem_policy_creator_cr
  filesystem_policy = { Version: "2012-10-17", Statement: [] }
  filesystem_policy[:Statement] << {
    Sid: "DefaultGrantTransferRoleAccess",
    Principal: {
      "AWS": "*"
    },
    Action: [
      "elasticfilesystem:ClientWrite",
      "elasticfilesystem:ClientMount",
      "elasticfilesystem:ClientRootAccess"
    ],
    Effect: "Allow"
  }

  users = external_parameters.fetch(:users, [])
  users.each do |user|

    if !user['name'].match?(/^[a-zA-Z0-9_][a-zA-Z0-9_-]{2,31}$/)
      raise "#{user['name']} is invalid, must comply with `^[a-zA-Z0-9_][a-zA-Z0-9_-]{2,31}$`"
    end

    user_tags = default_tags.map(&:clone)
    user_tags << { Key: "Name", Value: "#{user['name']}" }

    if domain.upcase == 'EFS'
      if user.has_key? 'access' and user['access'].include? 'root'
        IAM_Role("#{user['name']}SftpAccessRole") {
          AssumeRolePolicyDocument service_role_assume_policy('transfer')
          Path '/'
          Policies ([
            PolicyName: "sftp-write-access-for-#{user['name']}",
            PolicyDocument: {
              Statement: [
                {
                  Sid: "AllowWriteAccessToFileSystem",
                  Effect: "Allow",
                  Action: [
                    "elasticfilesystem:ClientWrite",
                    "elasticfilesystem:ClientMount"
                  ],
                  Resource: FnSub("arn:aws:elasticfilesystem:::#{user['filesystem']}")
                }
              ]
            }
          ])
        }
        Output("#{user['name']}SftpAccessRole") {
          Value Ref("#{user['name']}SftpAccessRole")
          Export FnSub("${EnvironmentName}-#{external_parameters[:component_name]}-#{user['name']}SftpAccessRole")
        }
        Output("#{user['name']}SftpAccessRoleArn") {
          Value FnGetAtt("#{user['name']}SftpAccessRole", :Arn)
          Export FnSub("${EnvironmentName}-#{external_parameters[:component_name]}-#{user['name']}SftpAccessRoleArn")
        }
        filesystem_policy[:Statement] << {
          Sid: "#{user['name']}SFTPRootGrantTransferRoleAccess",
          Principal: {
            "AWS": FnGetAtt("#{user['name']}SftpAccessRole", :Arn)
          },
          Action: [
            "elasticfilesystem:ClientWrite",
            "elasticfilesystem:ClientMount",
            "elasticfilesystem:ClientRootAccess"
          ],
          Effect: "Allow"
        }
      elsif user.has_key? 'access' and user['access'].include? 'write'
        IAM_Role("#{user['name']}SftpAccessRole") {
          AssumeRolePolicyDocument service_role_assume_policy('transfer')
          Path '/'
          Policies ([
            PolicyName: "sftp-write-access-for-#{user['name']}",
            PolicyDocument: {
              Statement: [
                {
                  Sid: "AllowWriteAccessToFileSystem",
                  Effect: "Allow",
                  Action: [
                    "elasticfilesystem:ClientWrite",
                    "elasticfilesystem:ClientMount"
                  ],
                  Resource: FnSub("arn:aws:elasticfilesystem:::#{user['filesystem']}")
                }
              ]
            }
          ])
        }
        Output("#{user['name']}SftpAccessRole") {
          Value Ref("#{user['name']}SftpAccessRole")
          Export FnSub("${EnvironmentName}-#{external_parameters[:component_name]}-#{user['name']}SftpAccessRole")
        }
        Output("#{user['name']}SftpAccessRoleArn") {
          Value FnGetAtt("#{user['name']}SftpAccessRole", :Arn)
          Export FnSub("${EnvironmentName}-#{external_parameters[:component_name]}-#{user['name']}SftpAccessRoleArn")
        }
        filesystem_policy[:Statement] << {
          Sid: "#{user['name']}SFTPReadWriteGrantTransferRoleAccess",
          Principal: {
            "AWS": FnGetAtt("#{user['name']}SftpAccessRole", :Arn)
          },
          Action: [
            "elasticfilesystem:ClientWrite",
            "elasticfilesystem:ClientMount"
          ],
          Effect: "Allow"
        }
      elsif user.has_key? 'access' and user['access'].include? 'read'
        IAM_Role("#{user['name']}SftpAccessRole") {
          AssumeRolePolicyDocument service_role_assume_policy('transfer')
          Path '/'
          Policies ([
            PolicyName: "sftp-read-access-for-#{user['name']}",
            PolicyDocument: {
              Statement: [
                {
                  Sid: "AllowReadAccessToFileSystem",
                  Effect: "Allow",
                  Action: [
                    "elasticfilesystem:ClientMount"
                  ],
                  Resource: FnSub("arn:aws:elasticfilesystem:::#{user['filesystem']}")
                }
              ]
            }
          ])
        }
        Output("#{user['name']}SftpAccessRole") {
          Value Ref("#{user['name']}SftpAccessRole")
          Export FnSub("${EnvironmentName}-#{external_parameters[:component_name]}-#{user['name']}SftpAccessRole")
        }
        Output("#{user['name']}SftpAccessRoleArn") {
          Value FnGetAtt("#{user['name']}SftpAccessRole", :Arn)
          Export FnSub("${EnvironmentName}-#{external_parameters[:component_name]}-#{user['name']}SftpAccessRoleArn")
        }
        filesystem_policy[:Statement] << {
          Sid: "#{user['name']}SFTPReadGrantTransferRoleAccess",
          Principal: {
            "AWS": FnGetAtt("#{user['name']}SftpAccessRole", :Arn)
          },
          Action: [
            "elasticfilesystem:ClientMount"
          ],
          Effect: "Allow"
        }
      end
    elsif domain.upcase == 'S3'
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
      Output("#{user['name']}SftpAccessRole") {
        Value Ref("#{user['name']}SftpAccessRole")
        Export FnSub("${EnvironmentName}-#{external_parameters[:component_name]}-#{user['name']}SftpAccessRole")
      }
      Output("#{user['name']}SftpAccessRoleArn") {
        Value FnGetAtt("#{user['name']}SftpAccessRole", :Arn)
        Export FnSub("${EnvironmentName}-#{external_parameters[:component_name]}-#{user['name']}SftpAccessRoleArn")
      }

      user_policy = { Version: "2012-10-17", Statement: [] }

      if user.has_key?('home') && user['home'] == '/'
        user_policy[:Statement] << {
          Sid: "AllowListingOfUserFolder",
          Action: [ "s3:ListBucket" ],
          Effect: "Allow",
          Resource: [ "arn:aws:s3:::${!transfer:HomeBucket}" ]
        }
      else
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
      end    

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
    end

    if identity_provider.upcase == 'API_GATEWAY'

      secret_string = { Role: "${Role}" }
      
      if user.has_key? 'bucket' && domain.upcase == 'S3'
        secret_string[:HomeDirectory] = user.has_key?('home') ? "/#{user['bucket']}#{user['home']}" : "/#{user['bucket']}/home/#{user['name']}"
      else
        secret_string[:HomeDirectory] = user.has_key?('home') ? "/#{user['filesystem']}#{user['home']}" : "/#{user['filesystem']}/home/#{user['name']}"
      end
      
      secret_string[:Policy] = user_policy.to_json

      if user.has_key? 'keys' and user['keys'].any?
        secret_string[:PublicKeys] = user['keys']
      end

      SecretsManager_Secret("#{user['name']}SftpUserSecret") {
        Name FnSub("sftp/${EnvironmentName}/#{user['name']}")
        Description FnSub("${EnvironmentName} sftp user details for #{user['name']}")
        SecretString FnSub(secret_string.to_json, { Role: FnGetAtt("#{user['name']}SftpAccessRole", :Arn) })
      }

    else
      if user.has_key? 'bucket' && domain.upcase == 'S3'
        home_directory = user.has_key?('home') ? "/#{user['bucket']}#{user['home']}" : "/#{user['bucket']}/home/#{user['name']}"
      else
        home_directory = user.has_key?('home') ? "/#{user['filesystem']}#{user['home']}" : "/#{user['filesystem']}/home/#{user['name']}"
      end

      Transfer_User("#{user['name']}SftpUser") {
        Condition(:TransferServerEnabled)
        UserName user['name']
        ServerId FnGetAtt(:SftpServer, :ServerId)
        Role FnGetAtt("#{user['name']}SftpAccessRole", :Arn)
        
        if user.has_key? 'home_directory_type' and user['home_directory_type'].upcase == 'LOGICAL' and user.has_key? 'home_directory_mappings' and user['home_directory_mappings'].any?
          HomeDirectoryType 'LOGICAL'
          home_mappings = []
          user['home_directory_mappings'].each do |map|
            mapping = {}
            mapping[:Entry] = map['entry']
            mapping[:Target] = FnSub(map['target'])
            home_mappings.push(mapping)
          end
          HomeDirectoryMappings home_mappings
        else
          HomeDirectoryType 'PATH'
          HomeDirectory FnSub(home_directory)
        end

        if domain.upcase == 'S3'
          Policy FnSub(user_policy.to_json)
        end
        
        if user.has_key? 'keys' and user['keys'].any?
          SshPublicKeys user['keys']
        end
        
        if user.has_key? 'posix'
          posix_profile = {}
          posix_profile[:Gid] = user['posix']['Gid'] if user['posix'].has_key?('Gid')
          posix_profile[:Uid] = user['posix']['Uid'] if user['posix'].has_key?('Uid')
          PosixProfile posix_profile
        end
        
        Tags user_tags
      }
    end
  end

  if domain.upcase == 'EFS'
    Resource("FileSystemPolicyCreatorFunction") do
      Type 'AWS::CloudFormation::CustomResource'
      Property 'ServiceToken', FnGetAtt('FilesystemPolicyCreatorCR','Arn')
      Property 'FunctionName', Ref('FilesystemPolicyCreatorCR')
      Property 'Policy', filesystem_policy
      Property 'FileSystemId', Ref('FileSystemId')
    end
  end

  Route53_RecordSet(:SftpServerRecord) {
    Condition('IfDns')
    HostedZoneName FnSub("#{dns_format}.")
    Name FnSub("#{server_name}.#{dns_format}.")
    Type 'CNAME'
    TTL '60'
    Comment FnJoin("", [Ref('EnvironmentName') ," sftp server ", FnGetAtt(:SftpServer,:ServerId)])
    ResourceRecords [ FnJoin('.',[ FnGetAtt(:SftpServer, :ServerId), 'server.transfer', Ref('AWS::Region'), 'amazonaws.com' ]) ]
  }

  Output(:SftpServerId) {
      Value(
        FnIf(:TransferServerEnabled,
          FnGetAtt(:SftpServer, :ServerId),
          ""
        )
      )
  }
  Output(:SftpServerEndpoint) { 
    Value(
      FnIf(:TransferServerEnabled,
        FnJoin('.',[ FnGetAtt(:SftpServer, :ServerId), 'server.transfer', Ref('AWS::Region'), 'amazonaws.com' ]),
        ""
      )
    )
  }
end