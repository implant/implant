#!/bin/bash

source ./functions.sh

test_encode_password() {
  assertEquals "gu%407%3E7M8KA%23rt9r)" "$(url_encode "gu@7>7M8KA#rt9r)")"
}

test_get_package_strips_path_and_extension() {
  assertEquals "org.tasks" "$(get_package "./metadata/org.tasks.yml")"
}

test_get_subdir_from_project() {
  assertEquals "project" "$(get_subdir "project/app")"
}

test_get_empty_subdir() {
  assertEquals "." "$(get_subdir "app")"
}

test_get_project_from_project() {
  assertEquals "app" "$(get_project "project/app")"
}

test_get_project_no_subdir() {
  assertEquals "app" "$(get_project "app")"
}

source ./shunit2
