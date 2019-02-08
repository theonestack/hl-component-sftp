CloudFormation do

  Condition('Dns', FnNot(FnEquals(Ref('DnsDomain'), '')))

  default_tags = []
  default_tags << { Key: "Name", Value: FnSub('${ServerName}-${EnvironmentName}') }
  default_tags << { Key: "Environment", Value: Ref("EnvironmentName") }
  default_tags << { Key: "EnvironmentType", Value: Ref("EnvironmentType") }

  tags.each do |key, value|
    default_tags << { Key: key, Value: value }
  end if defined? tags

  # hack to set the a custom hostname for the SFTP server since you cant via the API
  default_tags_hostname = []
  default_tags_hostname += default_tags
  default_tags_hostname << { Key: "aws:transfer:customHostname", Value: FnSub('${ServerName}.${EnvironmentName}.${DnsDomain}') }

  IAM_Role('SftpServerLoggingRole') {
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

  Resource("SftpServer") do
    Type 'Custom::SftpServer'
    Property 'ServiceToken',FnGetAtt('SftpServerCR','Arn')
    Property 'Region', Ref('AWS::Region')
    Property 'LoggingRole', FnGetAtt('SftpServerLoggingRole','Arn')
    Property 'Tags', FnIf('Dns', default_tags_hostname , default_tags)
  end

  Route53_RecordSet('SftpServerRecord') {
    Condition('Dns')
    HostedZoneName FnJoin('', [ Ref('EnvironmentName'), '.', Ref('DnsDomain'), '.'])
    Name FnJoin('', [ Ref('ServerName'), '.', Ref('EnvironmentName'), '.', Ref('DnsDomain'), '.' ])
    Type 'CNAME'
    TTL '60'
    ResourceRecords [ FnGetAtt('SftpServer','StpServerEndpoint') ]
  }

  Output("SftpServer") { Value(Ref('SftpServer')) }
  Output("SftpServerEndpoint") { Value(FnGetAtt('SftpServer', 'StpServerEndpoint')) }

end