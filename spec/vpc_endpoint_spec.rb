require 'yaml'

describe 'compiled component sftp' do
  
  context 'cftest' do
    it 'compiles test' do
      expect(system("cfhighlander cftest #{@validate} --tests tests/vpc_endpoint.test.yaml")).to be_truthy
    end      
  end
  
  let(:template) { YAML.load_file("#{File.dirname(__FILE__)}/../out/tests/vpc_endpoint/sftp.compiled.yaml") }
  
  context "Resource" do

    
    context "SftpSecurityGroup" do
      let(:resource) { template["Resources"]["SftpSecurityGroup"] }

      it "is of type AWS::EC2::SecurityGroup" do
          expect(resource["Type"]).to eq("AWS::EC2::SecurityGroup")
      end
      
      it "to have property VpcId" do
          expect(resource["Properties"]["VpcId"]).to eq({"Ref"=>"VpcId"})
      end
      
      it "to have property GroupDescription" do
          expect(resource["Properties"]["GroupDescription"]).to eq({"Fn::Sub"=>"Controll sftp access to the sftp-${EnvironmentName} aws transfer server vpc endpoint"})
      end
      
      it "to have property SecurityGroupIngress" do
          expect(resource["Properties"]["SecurityGroupIngress"]).to eq([{"Description"=>{"Fn::Sub"=>"public sftp access"}, "FromPort"=>22, "IpProtocol"=>"TCP", "ToPort"=>22, "CidrIp"=>{"Fn::Sub"=>"0.0.0.0/0"}}])
      end
      
      it "to have property Tags" do
          expect(resource["Properties"]["Tags"]).to eq([{"Key"=>"Environment", "Value"=>{"Ref"=>"EnvironmentName"}}, {"Key"=>"EnvironmentType", "Value"=>{"Ref"=>"EnvironmentType"}}, {"Key"=>"Name", "Value"=>{"Fn::Sub"=>"sftp-${EnvironmentName}-sftp-access"}}])
      end
      
    end
    
    context "SftpVpcEndpoint" do
      let(:resource) { template["Resources"]["SftpVpcEndpoint"] }

      it "is of type AWS::EC2::VPCEndpoint" do
          expect(resource["Type"]).to eq("AWS::EC2::VPCEndpoint")
      end
      
      it "to have property VpcId" do
          expect(resource["Properties"]["VpcId"]).to eq({"Ref"=>"VpcId"})
      end
      
      it "to have property ServiceName" do
          expect(resource["Properties"]["ServiceName"]).to eq({"Fn::Sub"=>"com.amazonaws.${AWS::Region}.transfer.server"})
      end
      
      it "to have property VpcEndpointType" do
          expect(resource["Properties"]["VpcEndpointType"]).to eq("Interface")
      end
      
      it "to have property PrivateDnsEnabled" do
          expect(resource["Properties"]["PrivateDnsEnabled"]).to eq(true)
      end
      
      it "to have property SubnetIds" do
          expect(resource["Properties"]["SubnetIds"]).to eq({"Ref"=>"SubnetIds"})
      end
      
      it "to have property SecurityGroupIds" do
          expect(resource["Properties"]["SecurityGroupIds"]).to eq([{"Ref"=>"SftpSecurityGroup"}])
      end
      
    end
    
    context "GetVpcEndpointIPs" do
      let(:resource) { template["Resources"]["GetVpcEndpointIPs"] }

      it "is of type Custom::SftpServer" do
          expect(resource["Type"]).to eq("Custom::SftpServer")
      end
      
      it "to have property ServiceToken" do
          expect(resource["Properties"]["ServiceToken"]).to eq({"Fn::GetAtt"=>["GetVpcEndpointIPsCR", "Arn"]})
      end
      
      it "to have property NetworkInterfaceIds" do
          expect(resource["Properties"]["NetworkInterfaceIds"]).to eq({"Fn::GetAtt"=>["SftpVpcEndpoint", "NetworkInterfaceIds"]})
      end
      
    end
    
    context "SftpServerLoggingRole" do
      let(:resource) { template["Resources"]["SftpServerLoggingRole"] }

      it "is of type AWS::IAM::Role" do
          expect(resource["Type"]).to eq("AWS::IAM::Role")
      end
      
      it "to have property AssumeRolePolicyDocument" do
          expect(resource["Properties"]["AssumeRolePolicyDocument"]).to eq({"Version"=>"2012-10-17", "Statement"=>[{"Effect"=>"Allow", "Principal"=>{"Service"=>"transfer.amazonaws.com"}, "Action"=>"sts:AssumeRole"}]})
      end
      
      it "to have property Path" do
          expect(resource["Properties"]["Path"]).to eq("/")
      end
      
      it "to have property Policies" do
          expect(resource["Properties"]["Policies"]).to eq([{"PolicyName"=>"logging", "PolicyDocument"=>{"Statement"=>[{"Effect"=>"Allow", "Action"=>["logs:CreateLogStream", "logs:DescribeLogStreams", "logs:CreateLogGroup", "logs:PutLogEvents"], "Resource"=>"*"}]}}])
      end
      
    end
    
    context "SftpServer" do
      let(:resource) { template["Resources"]["SftpServer"] }

      it "is of type AWS::Transfer::Server" do
          expect(resource["Type"]).to eq("AWS::Transfer::Server")
      end
      
      it "to have property EndpointType" do
          expect(resource["Properties"]["EndpointType"]).to eq("VPC_ENDPOINT")
      end
      
      it "to have property EndpointDetails" do
          expect(resource["Properties"]["EndpointDetails"]).to eq({"VpcEndpointId"=>{"Ref"=>"SftpVpcEndpoint"}})
      end
      
      it "to have property IdentityProviderType" do
          expect(resource["Properties"]["IdentityProviderType"]).to eq("SERVICE_MANAGED")
      end
      
      it "to have property LoggingRole" do
          expect(resource["Properties"]["LoggingRole"]).to eq({"Fn::GetAtt"=>["SftpServerLoggingRole", "Arn"]})
      end
      
      it "to have property Tags" do
          expect(resource["Properties"]["Tags"]).to eq([{"Key"=>"Environment", "Value"=>{"Ref"=>"EnvironmentName"}}, {"Key"=>"EnvironmentType", "Value"=>{"Ref"=>"EnvironmentType"}}, {"Key"=>"Name", "Value"=>{"Fn::Sub"=>"sftp-${EnvironmentName}"}}])
      end
      
    end
    
    context "SftpServerRecord" do
      let(:resource) { template["Resources"]["SftpServerRecord"] }

      it "is of type AWS::Route53::RecordSet" do
          expect(resource["Type"]).to eq("AWS::Route53::RecordSet")
      end
      
      it "to have property HostedZoneName" do
          expect(resource["Properties"]["HostedZoneName"]).to eq({"Fn::Sub"=>"${EnvironmentName}.${DnsDomain}."})
      end
      
      it "to have property Name" do
          expect(resource["Properties"]["Name"]).to eq({"Fn::Sub"=>"sftp.${EnvironmentName}.${DnsDomain}."})
      end
      
      it "to have property Type" do
          expect(resource["Properties"]["Type"]).to eq("CNAME")
      end
      
      it "to have property TTL" do
          expect(resource["Properties"]["TTL"]).to eq("60")
      end
      
      it "to have property Comment" do
          expect(resource["Properties"]["Comment"]).to eq({"Fn::Join"=>["", [{"Ref"=>"EnvironmentName"}, " sftp server ", {"Fn::GetAtt"=>["SftpServer", "ServerId"]}]]})
      end
      
      it "to have property ResourceRecords" do
          expect(resource["Properties"]["ResourceRecords"]).to eq([{"Fn::Join"=>[".", [{"Fn::GetAtt"=>["SftpServer", "ServerId"]}, "server.transfer", {"Ref"=>"AWS::Region"}, "amazonaws.com"]]}])
      end
      
    end
    
    context "LambdaRoleGetVpcEndpointIPs" do
      let(:resource) { template["Resources"]["LambdaRoleGetVpcEndpointIPs"] }

      it "is of type AWS::IAM::Role" do
          expect(resource["Type"]).to eq("AWS::IAM::Role")
      end
      
      it "to have property AssumeRolePolicyDocument" do
          expect(resource["Properties"]["AssumeRolePolicyDocument"]).to eq({"Version"=>"2012-10-17", "Statement"=>[{"Effect"=>"Allow", "Principal"=>{"Service"=>"lambda.amazonaws.com"}, "Action"=>"sts:AssumeRole"}]})
      end
      
      it "to have property Path" do
          expect(resource["Properties"]["Path"]).to eq("/")
      end
      
      it "to have property Policies" do
          expect(resource["Properties"]["Policies"]).to eq([{"PolicyName"=>"cloudwatch-logs", "PolicyDocument"=>{"Statement"=>[{"Effect"=>"Allow", "Action"=>["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams", "logs:DescribeLogGroups"], "Resource"=>["arn:aws:logs:*:*:*"]}]}}, {"PolicyName"=>"describe-eips", "PolicyDocument"=>{"Statement"=>[{"Effect"=>"Allow", "Action"=>["ec2:DescribeNetworkInterfaces"], "Resource"=>"*"}]}}, {"PolicyName"=>"lambda", "PolicyDocument"=>{"Statement"=>[{"Effect"=>"Allow", "Action"=>["lambda:InvokeFunction"], "Resource"=>{"Fn::Sub"=>"arn:aws:lambda:${AWS::Region}:${AWS::AccountId}:function:GetVpcEndpointIPsCR"}}]}}])
      end
      
    end
    
    context "GetVpcEndpointIPsCR" do
      let(:resource) { template["Resources"]["GetVpcEndpointIPsCR"] }

      it "is of type AWS::Lambda::Function" do
          expect(resource["Type"]).to eq("AWS::Lambda::Function")
      end
      
      it "to have property Environment" do
          expect(resource["Properties"]["Environment"]).to eq({"Variables"=>{}})
      end
      
      it "to have property Handler" do
          expect(resource["Properties"]["Handler"]).to eq("index.handler")
      end
      
      it "to have property MemorySize" do
          expect(resource["Properties"]["MemorySize"]).to eq(128)
      end
      
      it "to have property Role" do
          expect(resource["Properties"]["Role"]).to eq({"Fn::GetAtt"=>["LambdaRoleGetVpcEndpointIPs", "Arn"]})
      end
      
      it "to have property Runtime" do
          expect(resource["Properties"]["Runtime"]).to eq("python3.11")
      end
      
      it "to have property Timeout" do
          expect(resource["Properties"]["Timeout"]).to eq(60)
      end
      
      it "to have property FunctionName" do
          expect(resource["Properties"]["FunctionName"]).to eq("GetVpcEndpointIPsCR")
      end
      
    end
    
    context "GetVpcEndpointIPsCRLogGroup" do
      let(:resource) { template["Resources"]["GetVpcEndpointIPsCRLogGroup"] }

      it "is of type AWS::Logs::LogGroup" do
          expect(resource["Type"]).to eq("AWS::Logs::LogGroup")
      end
      
      it "to have property LogGroupName" do
          expect(resource["Properties"]["LogGroupName"]).to eq("/aws/lambda/GetVpcEndpointIPsCR")
      end
      
      it "to have property RetentionInDays" do
          expect(resource["Properties"]["RetentionInDays"]).to eq(14)
      end
      
    end
    
  end

end