#!/usr/bin/env bash
# Packages lambda_snowflake_load.py + the Snowflake connector into a zip for AWS Lambda.
# The --platform flags download the Linux / Python 3.12 build that Lambda runs,
# no matter which Python version your own computer has.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build lambda_snowflake_load.zip
mkdir build

python3 -m pip install --quiet --target build \
  --platform manylinux2014_x86_64 --implementation cp --python-version 3.12 \
  --only-binary=:all: snowflake-connector-python

cp lambda_snowflake_load.py build/
(cd build && zip -qr ../lambda_snowflake_load.zip .)

ls -lh lambda_snowflake_load.zip
echo "Unzipped size:"; du -sh build
