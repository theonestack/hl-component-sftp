CfhighlanderTemplate do

  Parameters do
    ComponentParam 'EnvironmentName', 'dev', isGlobal: true
    ComponentParam 'EnvironmentType', 'development', allowedValues: ['development','production'], isGlobal: true
    ComponentParam 'ServerName', 'sftp'
    ComponentParam 'DnsDomain', ''
  end

  LambdaFunctions 'sftp_custom_resources'
end
