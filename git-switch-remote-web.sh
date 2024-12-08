#!/bin/bash

set -ex

# 第1引数からcurrent_branchを取得する
current_branch=$1

# ディレクトリ移動とgit操作
ssh isucon14-2 "cd ~/webapp && git fetch && git switch $current_branch && git pull origin $current_branch"
