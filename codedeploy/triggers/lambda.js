
const { CodeDeployClient, CreateDeploymentCommand } = require("@aws-sdk/client-codedeploy");

const codedeploy = new CodeDeployClient();

const APPLICATION_NAME = process.env.APPLICATION_NAME;
const DEPLOYMENT_GROUP_NAME = process.env.DEPLOYMENT_GROUP_NAME;

exports.handler = async (event) => {
    const params = {
        applicationName: APPLICATION_NAME,
        deploymentGroupName: DEPLOYMENT_GROUP_NAME,
        revision: {
            revisionType: 'S3',
            s3Location: {
                bucket: event.Records[0].s3.bucket.name,
                key: event.Records[0].s3.object.key,
                bundleType: 'zip'
            }
        }
    };

    try {
        const command = new CreateDeploymentCommand(params);
        const data = await codedeploy.send(command);
        console.log('Deployment started:', data.deploymentId);
    } catch (error) {
        console.error('Failed to start deployment:', error);
    }
};