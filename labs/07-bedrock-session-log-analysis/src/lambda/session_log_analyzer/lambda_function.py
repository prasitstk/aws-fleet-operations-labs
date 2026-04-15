"""Analyze SSM Session Manager logs using Amazon Bedrock.

Triggered by S3 PUT events when Session Manager uploads session transcripts.
Enriches analysis with CloudTrail metadata (who, when, where) and publishes
security-focused reports via SNS.
"""

import json
import logging
import os
import time
from datetime import datetime, timedelta, timezone

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client("s3")
sns = boto3.client("sns")
bedrock = boto3.client(
    "bedrock-runtime",
    region_name=os.environ.get("AWS_REGION_NAME", "us-east-1"),
)
cloudtrail = boto3.client("cloudtrail")

MODEL_ID = os.environ.get("MODEL_ID", "us.anthropic.claude-haiku-4-5-20251001-v1:0")
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN", "")

CLOUDTRAIL_WAIT_SECONDS = 120


def get_session_metadata(session_id):
    """Query CloudTrail for the StartSession event matching the given session ID.

    Returns a dict with user, account, instance, source_ip, and event_time.
    Falls back to 'Unknown*' values if no matching event is found.
    """
    try:
        start_time = datetime.now(timezone.utc) - timedelta(minutes=10)
        response = cloudtrail.lookup_events(
            LookupAttributes=[
                {"AttributeKey": "EventName", "AttributeValue": "StartSession"}
            ],
            StartTime=start_time,
            MaxResults=50,
        )

        for event in response.get("Events", []):
            event_data = json.loads(event["CloudTrailEvent"])
            trail_session = (
                event_data.get("responseElements", {}).get("sessionId", "")
            )
            if session_id.lower() in trail_session.lower():
                user_identity = event_data.get("userIdentity", {})
                return {
                    "user": user_identity.get(
                        "userName", user_identity.get("arn", "UnknownUser")
                    ),
                    "account": user_identity.get("accountId", "UnknownAccount"),
                    "instance": event_data.get("requestParameters", {}).get(
                        "target", "UnknownInstance"
                    ),
                    "source_ip": event_data.get(
                        "sourceIPAddress", "UnknownIP"
                    ),
                    "event_time": event_data.get("eventTime", "UnknownTime"),
                }

    except Exception as e:
        logger.error("CloudTrail lookup failed: %s", e)

    return {
        "user": "UnknownUser",
        "account": "UnknownAccount",
        "instance": "UnknownInstance",
        "source_ip": "UnknownIP",
        "event_time": "UnknownTime",
    }


def lambda_handler(event, context):
    """Process S3 PUT events for session log analysis via Bedrock."""
    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        key = record["s3"]["object"]["key"]
        logger.info("Processing session log: s3://%s/%s", bucket, key)

        # Extract session ID from S3 key (e.g. "session-logs/<session-id>.log")
        session_id = os.path.splitext(os.path.basename(key))[0]
        logger.info("Session ID: %s", session_id)

        # Wait for CloudTrail event propagation
        logger.info(
            "Waiting %ds for CloudTrail propagation...", CLOUDTRAIL_WAIT_SECONDS
        )
        time.sleep(CLOUDTRAIL_WAIT_SECONDS)

        # Fetch session metadata from CloudTrail
        metadata = get_session_metadata(session_id)
        logger.info("Session metadata: %s", json.dumps(metadata))

        # Read session log from S3
        try:
            obj = s3.get_object(Bucket=bucket, Key=key)
            log_data = obj["Body"].read().decode("utf-8")
        except Exception as e:
            logger.error("Failed to read S3 object: %s", e)
            log_data = f"Error reading log: {e}"

        # Construct security-focused analysis prompt
        prompt = (
            "You are a cloud operations security assistant.\n\n"
            f"This AWS Systems Manager session was initiated by IAM user "
            f"'{metadata['user']}' on EC2 instance '{metadata['instance']}' "
            f"in AWS account '{metadata['account']}'. The session began at "
            f"{metadata['event_time']} from IP address "
            f"{metadata['source_ip']}.\n\n"
            "Analyze the following session activity log and provide a concise "
            "security-focused report.\n\n"
            "Your response MUST follow this exact format:\n\n"
            "SESSION DETAILS:\n"
            "- Who initiated the session\n"
            "- Which EC2 instance was accessed\n"
            "- The AWS account and source IP involved\n"
            "- When the session started\n\n"
            "SUMMARY:\n"
            "- Briefly describe the key actions performed (1-3 bullet points)\n\n"
            "RISK RATING:\n"
            "- Classify as one of: No-Risk, Low-Risk, Medium-Risk, High-Risk\n\n"
            "JUSTIFICATION:\n"
            "- Bullet points explaining why the rating was assigned\n\n"
            "--- SESSION LOG START ---\n"
            f"{log_data}\n"
            "--- SESSION LOG END ---"
        )

        # Invoke Bedrock model
        payload = {
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 800,
            "temperature": 0.3,
            "messages": [
                {"role": "user", "content": [{"type": "text", "text": prompt}]}
            ],
        }

        try:
            response = bedrock.invoke_model(
                modelId=MODEL_ID, body=json.dumps(payload)
            )
            result = json.loads(response["body"].read())
            analysis = result["content"][0]["text"]

            usage = result.get("usage", {})
            logger.info(
                "Bedrock tokens - input: %s, output: %s",
                usage.get("input_tokens", "N/A"),
                usage.get("output_tokens", "N/A"),
            )
        except Exception as e:
            logger.error("Bedrock invocation failed: %s", e)
            analysis = f"Bedrock analysis failed: {e}"

        # Publish analysis to SNS
        try:
            sns.publish(
                TopicArn=SNS_TOPIC_ARN,
                Subject="AWS Session Log Analysis",
                Message=analysis,
            )
            logger.info("Analysis published to SNS topic")
        except Exception as e:
            logger.error("SNS publish failed: %s", e)
