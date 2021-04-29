require 'yaml'

describe 'compiled component sftp' do
  
  context 'cftest' do
    it 'compiles test' do
      expect(system("cfhighlander cftest #{@validate} --tests tests/vpc.test.yaml")).to be_truthy
    end      
  end
  
  let(:template) { YAML.load_file("#{File.dirname(__FILE__)}/../out/tests/vpc/sftp.compiled.yaml") }
  
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
    
    context "SftpEIP0" do
      let(:resource) { template["Resources"]["SftpEIP0"] }

      it "is of type AWS::EC2::EIP" do
          expect(resource["Type"]).to eq("AWS::EC2::EIP")
      end
      
      it "to have property Domain" do
          expect(resource["Properties"]["Domain"]).to eq("vpc")
      end
      
      it "to have property Tags" do
          expect(resource["Properties"]["Tags"]).to eq([{"Key"=>"Name", "Value"=>{"Fn::Sub"=>["${EnvironmentName}-sftp-${AZ}", {"AZ"=>{"Fn::Select"=>[0, {"Fn::GetAZs"=>{"Ref"=>"AWS::Region"}}]}}]}}])
      end
      
    end
    
    context "SftpEIP1" do
      let(:resource) { template["Resources"]["SftpEIP1"] }

      it "is of type AWS::EC2::EIP" do
          expect(resource["Type"]).to eq("AWS::EC2::EIP")
      end
      
      it "to have property Domain" do
          expect(resource["Properties"]["Domain"]).to eq("vpc")
      end
      
      it "to have property Tags" do
          expect(resource["Properties"]["Tags"]).to eq([{"Key"=>"Name", "Value"=>{"Fn::Sub"=>["${EnvironmentName}-sftp-${AZ}", {"AZ"=>{"Fn::Select"=>[1, {"Fn::GetAZs"=>{"Ref"=>"AWS::Region"}}]}}]}}])
      end
      
    end
    
    context "SftpEIP2" do
      let(:resource) { template["Resources"]["SftpEIP2"] }

      it "is of type AWS::EC2::EIP" do
          expect(resource["Type"]).to eq("AWS::EC2::EIP")
      end
      
      it "to have property Domain" do
          expect(resource["Properties"]["Domain"]).to eq("vpc")
      end
      
      it "to have property Tags" do
          expect(resource["Properties"]["Tags"]).to eq([{"Key"=>"Name", "Value"=>{"Fn::Sub"=>["${EnvironmentName}-sftp-${AZ}", {"AZ"=>{"Fn::Select"=>[2, {"Fn::GetAZs"=>{"Ref"=>"AWS::Region"}}]}}]}}])
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
          expect(resource["Properties"]["EndpointType"]).to eq("VPC")
      end
      
      it "to have property EndpointDetails" do
          expect(resource["Properties"]["EndpointDetails"]).to eq({"SecurityGroupIds"=>[{"Ref"=>"SftpSecurityGroup"}], "SubnetIds"=>{"Ref"=>"SubnetIds"}, "VpcId"=>{"Ref"=>"VpcId"}, "AddressAllocationIds"=>{"Fn::If"=>["CreateEIPs", {"Fn::If"=>["CreateEIP2", [{"Fn::GetAtt"=>["SftpEIP0", "AllocationId"]}, {"Fn::GetAtt"=>["SftpEIP1", "AllocationId"]}, {"Fn::GetAtt"=>["SftpEIP2", "AllocationId"]}], {"Fn::If"=>["CreateEIP1", [{"Fn::GetAtt"=>["SftpEIP0", "AllocationId"]}, {"Fn::GetAtt"=>["SftpEIP1", "AllocationId"]}], {"Fn::If"=>["CreateEIP0", [{"Fn::GetAtt"=>["SftpEIP0", "AllocationId"]}], ""]}]}]}, {"Ref"=>"EIPs"}]}})
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
    
    context "user1SftpAccessRole" do
      let(:resource) { template["Resources"]["user1SftpAccessRole"] }

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
          expect(resource["Properties"]["Policies"]).to eq([{"PolicyName"=>"sftp-access-for-user1", "PolicyDocument"=>{"Statement"=>[{"Sid"=>"AllowListingOfUserFolder", "Effect"=>"Allow", "Action"=>["s3:ListBucket", "s3:GetBucketLocation"], "Resource"=>{"Fn::Sub"=>"arn:aws:s3:::mybucket"}}, {"Sid"=>"HomeDirObjectAccess", "Effect"=>"Allow", "Action"=>["s3:PutObject", "s3:GetObject", "s3:DeleteObjectVersion", "s3:DeleteObject", "s3:GetObjectVersion"], "Resource"=>{"Fn::Sub"=>"arn:aws:s3:::mybucket/*"}}]}}])
      end
      
    end
    
    context "user1SftpUser" do
      let(:resource) { template["Resources"]["user1SftpUser"] }

      it "is of type AWS::Transfer::User" do
          expect(resource["Type"]).to eq("AWS::Transfer::User")
      end
      
      it "to have property HomeDirectory" do
          expect(resource["Properties"]["HomeDirectory"]).to eq({"Fn::Sub"=>"/mybucket/home/user1"})
      end
      
      it "to have property UserName" do
          expect(resource["Properties"]["UserName"]).to eq("user1")
      end
      
      it "to have property ServerId" do
          expect(resource["Properties"]["ServerId"]).to eq({"Fn::GetAtt"=>["SftpServer", "ServerId"]})
      end
      
      it "to have property Role" do
          expect(resource["Properties"]["Role"]).to eq({"Fn::GetAtt"=>["user1SftpAccessRole", "Arn"]})
      end
      
      it "to have property Policy" do
          expect(resource["Properties"]["Policy"]).to eq({"Fn::Sub"=>"{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"AllowListingOfUserFolder\",\"Action\":[\"s3:ListBucket\"],\"Effect\":\"Allow\",\"Resource\":[\"arn:aws:s3:::${!transfer:HomeBucket}\"],\"Condition\":{\"StringLike\":{\"s3:prefix\":[\"${!transfer:HomeFolder}/*\",\"${!transfer:HomeFolder}\"]}}},{\"Sid\":\"AWSTransferRequirements\",\"Effect\":\"Allow\",\"Action\":[\"s3:ListAllMyBuckets\",\"s3:GetBucketLocation\"],\"Resource\":\"*\"},{\"Sid\":\"HomeDirObjectGetAccess\",\"Effect\":\"Allow\",\"Action\":[\"s3:GetObject\",\"s3:GetObjectVersion\",\"s3:GetObjectACL\"],\"Resource\":\"arn:aws:s3:::${!transfer:HomeDirectory}*\"},{\"Sid\":\"HomeDirObjectDenyMkdirAccess\",\"Effect\":\"Deny\",\"Action\":[\"s3:PutObject\"],\"Resource\":\"arn:aws:s3:::${!transfer:HomeBucket}/*/\"}]}"})
      end
      
      it "to have property SshPublicKeys" do
          expect(resource["Properties"]["SshPublicKeys"]).to eq(["ssh-rsa AAAA", "ssh-rsa BBBB"])
      end
      
      it "to have property Tags" do
          expect(resource["Properties"]["Tags"]).to eq([{"Key"=>"Environment", "Value"=>{"Ref"=>"EnvironmentName"}}, {"Key"=>"EnvironmentType", "Value"=>{"Ref"=>"EnvironmentType"}}, {"Key"=>"Name", "Value"=>"user1"}])
      end
      
    end
    
    context "SftpServerRecord" do
      let(:resource) { template["Resources"]["SftpServerRecord"] }

      it "is of type AWS::Route53::RecordSet" do
          expect(resource["Type"]).to eq("AWS::Route53::RecordSet")
      end
      
      it "to have property HostedZoneName" do
          expect(resource["Properties"]["HostedZoneName"]).to eq({"Fn::Sub"=>"${DnsDomain}."})
      end
      
      it "to have property Name" do
          expect(resource["Properties"]["Name"]).to eq({"Fn::Sub"=>"sftp.${DnsDomain}."})
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
    
  end

end