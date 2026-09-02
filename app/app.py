import os
from flask import Flask, jsonify
import boto3
app = Flask(__name__)
BUCKET = os.environ["SENSITIVE_BUCKET"]
KEY = "production/customer-records.txt"
s3 = boto3.client("s3")
@app.get("/")
def home():
    return jsonify({"application":"Wiz Managed Identity Lab","identity_model":"EC2 instance profile -> wiz-lab-workload-role","message":"Use /identity and /lab-data for the demonstration."})
@app.get("/identity")
def identity():
    return jsonify(boto3.client("sts").get_caller_identity())
@app.get("/lab-data")
def lab_data():
    response = s3.get_object(Bucket=BUCKET, Key=KEY)
    return jsonify({"source":f"s3://{BUCKET}/{KEY}","data":response["Body"].read().decode("utf-8")})
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
