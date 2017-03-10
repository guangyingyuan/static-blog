#!/bin/bash

set -xe

echo "Start deploying ...."
hexo clean
hexo g
hexo d
