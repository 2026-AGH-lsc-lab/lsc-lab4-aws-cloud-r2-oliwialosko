#!/bin/bash
# Endpoint URLs for load testing
# Fill in after deploying with the URLs printed by each deploy script
export LAMBDA_ZIP_URL="https://p6sfe7jpvhmhv6jrryxfbgqsrm0frheu.lambda-url.us-east-1.on.aws/"        # e.g. https://<id>.lambda-url.us-east-1.on.aws
export LAMBDA_CONTAINER_URL="https://izrxoqdu4fudnk343m6gogyqcq0cuukw.lambda-url.us-east-1.on.aws/"  # e.g. https://<id>.lambda-url.us-east-1.on.aws
export FARGATE_URL="http://lsc-knn-alb-1172825513.us-east-1.elb.amazonaws.com"           # e.g. http://<alb-dns>.us-east-1.elb.amazonaws.com
export EC2_URL="http://3.230.159.10:8080"               # e.g. http://<public-ip>:8080
