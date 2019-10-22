#!/bin/bash

source ./env.sh
source ./fdroid.sh

setUp() {
  tmp=$(mktemp)
}

tearDown() {
  rm "$tmp"
}

test_size() {
  echo test >"$tmp"
  assertEquals "5" "$(get_size "$tmp")"
}

test_added_time() {
  assertEquals "1569510952000" "$(get_added_time "org.tasks")"
}

test_updated_time() {
  assertEquals "1571149676000" "$(get_updated_time "com.fsck.k9")"
}

source ./shunit2
